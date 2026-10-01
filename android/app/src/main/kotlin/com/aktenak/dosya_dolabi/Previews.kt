package com.aktenak.dosya_dolabi

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max

/**
 * Dosya küçük resimleri: PDF'in ilk sayfası ve resimler, JPEG baytı olarak.
 * Zip tabanlı belgeler (pptx, docx...) Dart tarafında işlenir.
 */
object Previews {
    private val imageExt = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "heic")

    /** [px]: en geniş kenar. Çizilemeyen dosyada (bozuk, şifreli) null. */
    fun render(path: String, px: Int): ByteArray? {
        val f = File(path)
        if (!f.isFile) return null
        val target = px.coerceIn(120, 1600)
        val ext = f.extension.lowercase()
        val bmp = when {
            ext == "pdf" -> pdfFirstPage(f, target)
            ext in imageExt -> image(f, target)
            else -> null
        } ?: return null
        return try {
            ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
        } finally {
            bmp.recycle()
        }
    }

    // PdfRenderer ve Page eski Android sürümlerinde AutoCloseable değildir; `use` yerine
    // açıkça kapatılır.
    private fun pdfFirstPage(f: File, width: Int): Bitmap? {
        val fd = ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
        var renderer: PdfRenderer? = null
        try {
            renderer = PdfRenderer(fd)
            if (renderer.pageCount == 0) return null
            val page = renderer.openPage(0)
            try {
                val h = (width.toFloat() * page.height / page.width).toInt().coerceIn(1, 4000)
                val bmp = Bitmap.createBitmap(width, h, Bitmap.Config.ARGB_8888)
                bmp.eraseColor(Color.WHITE)
                page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                return bmp
            } finally {
                page.close()
            }
        } finally {
            renderer?.close()
            fd.close()
        }
    }

    private fun image(f: File, longest: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        // Büyük fotoğrafı belleğe tam çözmeden küçük çöz.
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= longest) sample *= 2
        val decoded = BitmapFactory.decodeFile(
            f.path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null

        val rotated = rotateByExif(f, decoded)
        val scale = longest.toFloat() / max(rotated.width, rotated.height)
        val w = if (scale < 1f) (rotated.width * scale).toInt().coerceAtLeast(1) else rotated.width
        val h = if (scale < 1f) (rotated.height * scale).toInt().coerceAtLeast(1) else rotated.height

        // Saydam (png, gif, webp) resimler JPEG'e çevrilirken siyaha dönmesin: beyaz zemine çiz.
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(rotated, null, Rect(0, 0, w, h), null)
        if (rotated !== decoded) decoded.recycle()
        rotated.recycle()
        return out
    }

    @Suppress("DEPRECATION")
    private fun rotateByExif(f: File, bmp: Bitmap): Bitmap {
        val degrees = try {
            when (ExifInterface(f.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (e: Exception) {
            0
        }
        if (degrees == 0) return bmp
        val m = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }
}
