package com.mobi.scanner

import android.graphics.BitmapFactory
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Tesseract on the device, for the Indian scripts ML Kit cannot read
 * (lib/data/tesseract_ocr.dart). Models are read from `<dataDir>/tessdata`,
 * downloaded there by the Dart side. One page at a time, off the main thread.
 */
class TesseractOcr {
    private val worker = Executors.newSingleThreadExecutor()
    private var api: TessBaseAPI? = null
    private var loaded: String? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognize") return result.notImplemented()
        val image = call.argument<String>("imagePath")!!
        val dataDir = call.argument<String>("dataDir")!!
        val languages = call.argument<String>("languages")!!
        val hocr = call.argument<Boolean>("hocr") ?: false
        worker.execute {
            try {
                val text = recognize(image, dataDir, languages, hocr)
                MAIN.post { result.success(text) }
            } catch (e: Throwable) {
                MAIN.post { result.error("tesseract", e.message, null) }
            }
        }
    }

    private fun recognize(image: String, dataDir: String, languages: String, hocr: Boolean): String {
        val key = "$dataDir|$languages"
        val tess = api?.takeIf { loaded == key } ?: run {
            api?.recycle()
            val fresh = TessBaseAPI()
            if (!fresh.init(dataDir, languages)) {
                fresh.recycle()
                api = null
                loaded = null
                throw IllegalStateException("Tesseract could not load $languages")
            }
            api = fresh
            loaded = key
            fresh
        }
        val bitmap = BitmapFactory.decodeFile(File(image).path) ?: throw IllegalArgumentException("Unreadable image")
        try {
            tess.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            tess.setVariable("preserve_interword_spaces", "1")
            tess.setImage(bitmap)
            return if (hocr) tess.getHOCRText(0) else tess.getUTF8Text()
        } finally {
            tess.clear()
            bitmap.recycle()
        }
    }

    companion object {
        const val CHANNEL = "lumascan/tesseract"
        private val MAIN = android.os.Handler(android.os.Looper.getMainLooper())
    }
}
