#include "detector.hpp"

#include <algorithm>
#include <cstdio>

namespace plapper {

void Detector::prepare() {
  const double sr = cfg_.sample_rate;
  hp1_.prepare(sr, cfg_.hpf_hz);
  hp2_.prepare(sr, cfg_.hpf_hz);
  envHp_.prepare(sr, cfg_.env_attack_ms, cfg_.env_release_ms);
  envFull_.prepare(sr, cfg_.env_attack_ms, cfg_.env_release_ms);
  releaseMs_.store(cfg_.env_release_ms, std::memory_order_relaxed);
  appliedReleaseMs_ = cfg_.env_release_ms;

  /* floor: falls fast (tau ~80 ms), rises slow (tau ~2.5 s) so a clap
   * burst barely inflates it */
  floorDown_ = 1.0f - std::exp(-1.0f / (float(sr) * 0.080f));
  floorUp_   = 1.0f - std::exp(-1.0f / (float(sr) * 2.5f));

  samplesPerMs_ = std::max(1, int(sr / 1000.0));
  lookbackSlots_ = std::clamp(int(cfg_.rise_lookback_ms), 1, kHist - 1);

  confirmSamples_ = int(kConfirmMs * 0.001f * sr);
  decaySamples_ = int(cfg_.decay_check_ms * 0.001f * sr);
  refractorySamples_ = int(cfg_.refractory_ms * 0.001f * sr);
  warmup_ = int(cfg_.warmup_ms * 0.001f * sr);
  sensitivityDb_.store(cfg_.sensitivity_db, std::memory_order_relaxed);
}

bool Detector::riseOk() const {
  if (histFilled_ < lookbackSlots_ + 1) return false;
  int idx = histPos_ - lookbackSlots_;
  if (idx < 0) idx += kHist;
  const float past = hist_[size_t(idx)];
  return db_from_lin(envHp_.value()) - db_from_lin(past) >= cfg_.rise_db;
}

int32_t Detector::process(const float* mono, int32_t n) {
  int32_t claps = 0;

  const float rel = releaseMs_.load(std::memory_order_relaxed);
  if (rel != appliedReleaseMs_ && rel > 0.5f) {
    appliedReleaseMs_ = rel;
    envHp_.setRelease(rel);
    envFull_.setRelease(rel);
  }

  for (int32_t i = 0; i < n; ++i) {
    const float x = mono[i];
    const float hp = hp2_.process(hp1_.process(x));

    const float eHp = envHp_.process(hp);
    const float eFull = envFull_.process(x);

    /* sliding window: ZCR on the high-passed signal (raw is LF-dominated in
     * real rooms and masks clap crossings), RMS sums per band.
     * winPos_ holds the OLDEST sample (about to be overwritten); the pair
     * leaving the window is (oldest, second-oldest). */
    const int8_t s = hp >= 0.0f ? 1 : -1;
    if (winFilled_ >= kWin) {
      const int secondOldest = (winPos_ + 1) % kWin;
      if (signs_[size_t(winPos_)] != signs_[size_t(secondOldest)] &&
          zcrCount_ > 0)
        --zcrCount_;
    }
    const int prev = winPos_ == 0 ? kWin - 1 : winPos_ - 1;
    if (winFilled_ > 0 && s != signs_[size_t(prev)]) ++zcrCount_;
    signs_[size_t(winPos_)] = s;
    sumHpSq_ += double(hp) * hp - hpSq_[size_t(winPos_)];
    sumFullSq_ += double(x) * x - fullSq_[size_t(winPos_)];
    hpSq_[size_t(winPos_)] = hp * hp;
    fullSq_[size_t(winPos_)] = x * x;
    winPos_ = (winPos_ + 1) % kWin;
    winFilled_ = std::min(winFilled_ + 1, kWin);

    /* noise floor tracks the detection-band envelope; frozen during
     * refractory so clap tails don't inflate it */
    if (refractory_ <= 0) {
      const float c = eHp < floor_ ? floorDown_ : floorUp_;
      floor_ += (eHp - floor_) * c;
    }

    /* 1 ms decimated envelope history for the attack gate */
    if (++histDecim_ >= samplesPerMs_) {
      histDecim_ = 0;
      hist_[size_t(histPos_)] = eHp;
      histPos_ = (histPos_ + 1) % kHist;
      histFilled_ = std::min(histFilled_ + 1, kHist);
    }

    if (warmup_ > 0) { --warmup_; continue; }
    if (refractory_ > 0) { --refractory_; continue; }

    const float eHpDb = db_from_lin(eHp);
    const float floorDb = db_from_lin(floor_);
    const float thresholdDb =
        std::max(floorDb + sensitivityDb_.load(std::memory_order_relaxed),
                 cfg_.min_level_db);
    const bool above = eHpDb > thresholdDb;

    if (!armed_ && (eHpDb < thresholdDb || eHpDb < rearmBelowDb_)) {
      armed_ = true;
    }

    if (pending_ > 0) {
      if (--pending_ == 0) {
        const float bandRatio =
            sumFullSq_ > 1e-12 ? float(std::sqrt(sumHpSq_ / sumFullSq_)) : 0.0f;
        const float zcr =
            winFilled_ >= kWin ? float(zcrCount_) / float(kWin) : 0.0f;
        const bool rise = riseOk();
        const bool pass = rise && bandRatio >= cfg_.band_ratio_min &&
                          zcr >= cfg_.zcr_min;
        if (debugLog_.load(std::memory_order_relaxed)) {
          std::fprintf(stderr,
                       "[plapper] candidate: env=%.1fdB floor=%.1fdB "
                       "rise=%s ratio=%.2f(min %.2f) zcr=%.3f(min %.3f) -> %s\n",
                       eHpDb, floorDb, rise ? "ok" : "FAIL", bandRatio,
                       cfg_.band_ratio_min, zcr, cfg_.zcr_min,
                       pass ? "decay-check" : "reject");
        }
        if (pass) {
          envConfirmDb_ = eHpDb;
          decayPending_ = decaySamples_;
        } else {
          armed_ = false;
          rearmBelowDb_ = eHpDb - cfg_.rearm_drop_db;
        }
      }
    } else if (decayPending_ > 0) {
      if (--decayPending_ == 0) {
        /* claps are over in ~100 ms; sustained broadband onsets (fan
         * turning on) stay loud and get rejected here */
        const bool decayed = eHpDb <= envConfirmDb_ - cfg_.decay_drop_db;
        if (debugLog_.load(std::memory_order_relaxed)) {
          std::fprintf(stderr,
                       "[plapper] decay: env=%.1fdB confirm=%.1fdB "
                       "need<=%.1fdB -> %s\n",
                       eHpDb, envConfirmDb_,
                       envConfirmDb_ - cfg_.decay_drop_db,
                       decayed ? "COUNT" : "reject");
        }
        armed_ = false;
        rearmBelowDb_ = eHpDb - cfg_.rearm_drop_db;
        if (decayed) {
          count_.fetch_add(1, std::memory_order_relaxed);
          ++claps;
          refractory_ = refractorySamples_;
        }
      }
    } else if (armed_ && above) {
      pending_ = confirmSamples_;
    }
  }

  envHpDbShared_.store(db_from_lin(envHp_.value()), std::memory_order_relaxed);
  envFullDbShared_.store(db_from_lin(envFull_.value()), std::memory_order_relaxed);
  floorDbShared_.store(db_from_lin(floor_), std::memory_order_relaxed);
  return claps;
}

}  // namespace plapper
