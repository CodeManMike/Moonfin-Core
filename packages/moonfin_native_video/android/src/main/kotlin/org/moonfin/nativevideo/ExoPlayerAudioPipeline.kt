package org.moonfin.nativevideo

import android.media.audiofx.LoudnessEnhancer

class ExoPlayerAudioPipeline {
    private var loudnessEnhancer: LoudnessEnhancer? = null

    var normalizationGainDb: Float? = null
        set(value) {
            field = value
            applyGain()
        }

    fun setAudioSessionId(audioSessionId: Int) {
        loudnessEnhancer?.release()
        loudnessEnhancer = runCatching {
            LoudnessEnhancer(audioSessionId)
        }.getOrNull()
        applyGain()
    }

    fun release() {
        loudnessEnhancer?.release()
        loudnessEnhancer = null
    }

    private fun applyGain() {
        val enhancer = loudnessEnhancer ?: return
        val targetGain = normalizationGainDb?.times(100f)?.toInt()
        runCatching {
            enhancer.setEnabled(targetGain != null)
            enhancer.setTargetGain(targetGain ?: 0)
        }.onFailure {
            loudnessEnhancer?.release()
            loudnessEnhancer = null
        }
    }
}
