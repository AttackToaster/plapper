#include "detector.hpp"

#include <algorithm>

namespace plounter {

void Detector::prepare() {
  const double sr = cfg_.sample_rate;
  hp1_.prepare(sr, cfg_.hpf_hz);
  hp2_.prepare(sr, cfg_.hpf_hz);
  envHp_.prepare(sr, 1.0f, 40.0f);
  envFull_.prepare(sr, 1.0f, 40.0f);

  /* floor: falls fast (tau ~80 ms), rises slow (tau ~2.5 s) so a clap
   * burst barely inflates it */
  floorDown_ = 1.0f - std::exp(-1.0f / (float(sr) * 0.080f));
  floorUp_   = 1.0f - std::exp(-1.0f / (float(sr) * 2.5f));

  samplesPerMs_ = std::max(1, int(sr / 1000.0));
  lookbackSlots_ = std::clamp(int(cfg_.rise_lookback_ms), 1, kHist - 1);

  confirmSamples_ = int(kConfirmMs * 0.001f * sr);
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

  for (int32_t i = 0; i < n; ++i) {
    const float x = mono[i];
    const float hp = hp2_.process(hp1_.process(x));

    const float eHp = envHp_.process(hp);
    const float eFull = envFull_.process(x);

    /* sliding window: ZCR on raw sign changes, RMS sums per band */
    const int8_t s = x >= 0.0f ? 1 : -1;
    if (winFilled_ >= kWin) {
      const int leaving = (winPos_ + 1) % kWin;
      if (signs_[size_t(winPos_ == 0 ? kWin - 1 : winPos_ - 1)] !=
          signs_[size_t(leaving)])
        --zcrCount_;  /* the pair (leaving, leaving+1) exits the window */
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

    if (pending_ > 0) {
      if (--pending_ == 0) {
        const float bandRatio =
            sumFullSq_ > 1e-12 ? float(std::sqrt(sumHpSq_ / sumFullSq_)) : 0.0f;
        const float zcr =
            winFilled_ >= kWin ? float(zcrCount_) / float(kWin) : 0.0f;
        if (riseOk() && bandRatio >= cfg_.band_ratio_min &&
            zcr >= cfg_.zcr_min) {
          count_.fetch_add(1, std::memory_order_relaxed);
          ++claps;
          refractory_ = refractorySamples_;
        }
      }
    } else if (above && !wasAbove_) {
      pending_ = confirmSamples_;
    }
    wasAbove_ = above;
  }

  envHpDbShared_.store(db_from_lin(envHp_.value()), std::memory_order_relaxed);
  floorDbShared_.store(db_from_lin(floor_), std::memory_order_relaxed);
  return claps;
}

}  // namespace plounter
