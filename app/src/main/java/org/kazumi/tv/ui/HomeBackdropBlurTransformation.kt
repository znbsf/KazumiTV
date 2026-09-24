package org.kazumi.tv.ui

import android.graphics.Bitmap
import coil.size.Size
import coil.transform.Transformation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/** Makes a bounded, reusable ambient image from a portrait cover without cropping its subject. */
internal class HomeBackdropBlurTransformation : Transformation {
    override val cacheKey: String = "org.kazumi.tv.home-backdrop-blur.v1"

    override suspend fun transform(input: Bitmap, size: Size): Bitmap = withContext(Dispatchers.Default) {
        val maxDimension = 720
        val scale = minOf(1f, maxDimension.toFloat() / maxOf(input.width, input.height))
        val width = (input.width * scale).roundToInt().coerceAtLeast(1)
        val height = (input.height * scale).roundToInt().coerceAtLeast(1)
        val software = if (input.config?.name == "HARDWARE") {
            input.copy(Bitmap.Config.ARGB_8888, false) ?: return@withContext input
        } else input
        val reduced = Bitmap.createScaledBitmap(software, width, height, true)
        val pixels = IntArray(width * height)
        reduced.getPixels(pixels, 0, width, 0, 0, width, height)
        if (reduced !== input) reduced.recycle()
        if (software !== input && software !== reduced) software.recycle()
        var blurred = pixels
        repeat(3) {
            blurred = blurLine(blurred, width, height, radius = 10, horizontal = true)
            blurred = blurLine(blurred, width, height, radius = 10, horizontal = false)
        }
        Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
            density = input.density
            setPixels(blurred, 0, width, 0, 0, width, height)
        }
    }

    private fun blurLine(source: IntArray, width: Int, height: Int, radius: Int, horizontal: Boolean): IntArray {
        val output = IntArray(source.size)
        val length = if (horizontal) width else height
        val lines = if (horizontal) height else width
        val window = radius * 2 + 1
        fun index(position: Int, line: Int) = if (horizontal) line * width + position else position * width + line
        for (line in 0 until lines) {
            var red = 0
            var green = 0
            var blue = 0
            for (offset in -radius..radius) {
                val pixel = source[index(offset.coerceIn(0, length - 1), line)]
                red += pixel shr 16 and 0xFF
                green += pixel shr 8 and 0xFF
                blue += pixel and 0xFF
            }
            for (position in 0 until length) {
                output[index(position, line)] = (0xFF shl 24) or
                    ((red / window) shl 16) or ((green / window) shl 8) or (blue / window)
                val leaving = source[index((position - radius).coerceIn(0, length - 1), line)]
                val entering = source[index((position + radius + 1).coerceIn(0, length - 1), line)]
                red += (entering shr 16 and 0xFF) - (leaving shr 16 and 0xFF)
                green += (entering shr 8 and 0xFF) - (leaving shr 8 and 0xFF)
                blue += (entering and 0xFF) - (leaving and 0xFF)
            }
        }
        return output
    }
}
