package com.mobi.scanner

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app lock's check that the phone's owner is holding it: fingerprint or
 * face where the phone has them, with the phone's PIN, pattern or password
 * always offered as well. Dart calls it through the `lumascan/device_auth`
 * channel.
 *
 * Uses the platform BiometricPrompt (Android 10+) or the lock screen's own
 * confirm screen (Android 8 and 9), so MainActivity can stay a plain
 * FlutterActivity for the first-frame watchdog.
 *
 * `authenticate` answers "success", "cancelled", "unavailable" (no screen
 * lock is set) or "failed" (for example, too many tries).
 */
class DeviceAuth(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(keyguard().isDeviceSecure)
            "authenticate" -> authenticate(call.argument<String>("reason") ?: "", result)
            else -> result.notImplemented()
        }
    }

    private fun keyguard() = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

    private fun authenticate(reason: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.success("cancelled")
            return
        }
        if (!keyguard().isDeviceSecure) {
            result.success("unavailable")
            return
        }
        pending = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) prompt(reason) else confirmCredential(reason)
    }

    private fun prompt(reason: String) {
        val builder = BiometricPrompt.Builder(activity)
            .setTitle(activity.applicationInfo.loadLabel(activity.packageManager))
            .setSubtitle(reason)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
        }
        builder.build().authenticate(
            CancellationSignal(),
            activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = finish("success")

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = finish(
                    when (errorCode) {
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_NEGATIVE_BUTTON -> "cancelled"
                        BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL -> "unavailable"
                        else -> "failed"
                    },
                )
            },
        )
    }

    /** Android 8 and 9: the lock screen's PIN, pattern or password screen. */
    private fun confirmCredential(reason: String) {
        @Suppress("DEPRECATION")
        val intent = keyguard().createConfirmDeviceCredentialIntent(
            activity.applicationInfo.loadLabel(activity.packageManager),
            reason,
        )
        if (intent == null) {
            finish("unavailable")
            return
        }
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST_CODE)
    }

    /** Called from MainActivity.onActivityResult; true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        finish(if (resultCode == Activity.RESULT_OK) "success" else "cancelled")
        return true
    }

    private fun finish(outcome: String) {
        val result = pending ?: return
        pending = null
        result.success(outcome)
    }

    companion object {
        const val CHANNEL = "lumascan/device_auth"
        private const val REQUEST_CODE = 4021
    }
}
