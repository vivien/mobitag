require 'chunky_png'

module ChunkyPNG
  # Add comparison methods to the ChunkyPNG::Color module
  module Color

    # Calculates the difference using weighting based on luminosity
    # http://stackoverflow.com/a/3968341
    #
    # 0 means they are equal, 100 means they are opposite
    def difference(c1, c2)
      grayscale1 = ChunkyPNG::Color.grayscale_teint(c1)
      grayscale2 = ChunkyPNG::Color.grayscale_teint(c2)

      (grayscale1 - grayscale2) * 100.0 / 256.0
    end

    def alike?(c1, c2, tolerance = 5)
      difference(c1, c2) < tolerance
    end
  end

  class Canvas
    # This module is like any other ChunkyPNG module.
    # It provides methods for operations on binary images.
    module Binary
      def binary!(mask_color, tolerance = 5)
        pixels.map! { |pixel| ChunkyPNG::Color.alike?(pixel, mask_color, tolerance) ? ChunkyPNG::Color::BLACK : ChunkyPNG::Color::WHITE }
        return self
      end

      def binary(mask_color, tolerance = 5)
        dup.binary!(mask_color, tolerance)
      end

      def dilate
        # See: https://github.com/wvanbergen/chunky_png/blob/master/lib/chunky_png/canvas/masking.rb#L85
        # to detect the mask color / bg color
      end
    end
  end
end

module Mobitag
  class Captcha < ChunkyPNG::Canvas

    # Wrapper module for the "stream" ImageMagick tool
    module Stream
      def self.extended(klass)
        raise "missing stream executable. please install imagemagick package" unless stream?
      end

      def self.stream?
        %x(stream -version) and true rescue false
      end

      # Return an array containing the width and height of an image
      # FIXME this creates a ./-verbose file...
      def dimensions(filename)
        %x(stream #{filename} -identify -verbose).match(/(\d+)x(\d+)/).captures.map &:to_i
      end

      # Get the RGB stream of an image
      def rgb_stream(filename)
        %x(stream #{filename} -)
      end

      # Extracted from ChunkyPNG::Canvas::StreamImporting.from_rgb_stream()
      def rgb_stream_to_pixels(width, height, stream)
        string = stream[0, 3 * width * height]
        string << ChunkyPNG::EXTRA_BYTE # Add a fourth byte to the last RGB triple.
        unpacker = 'NX' * (width * height)
        string.unpack(unpacker).map { |color| color | 0x000000ff }
      end

      # Module functions become private class methods
      module_function :dimensions, :rgb_stream, :rgb_stream_to_pixels
    end

    extend Stream
    include Binary

    # Approximate Captcha characters color (around r, g, b = 125, 65, 5)
    CHARS_COLOR = ChunkyPNG::Color("#7D4105") # average of samples
    #CHARS_COLOR = ChunkyPNG::Color("#885004") # from a sample

    # Load a captcha image from any image file format.
    #
    # It uses the "stream" ImageMagick tool to get the RGB
    # stream of any image format, then create a new ChunkyPNG
    # image from that stream (faster than reading a PNG file).
    def self.from_any_file(filename)
      width, height = dimensions(filename)
      pixels = rgb_stream_to_pixels(width, height, rgb_stream(filename))
      self.new(width, height, pixels)
    end

    def mask!
      binary!(CHARS_COLOR, 10)
    end

    def mask
      dup.mask!
    end

    def solve
      raise NotImplementedError, "You should wait a bit... :("
    end
  end
end



if __FILE__ == $0
  file = ARGV.first or raise
  captcha = Mobitag::Captcha.from_any_file(file)
  captcha.mask.save("captcha/binary.png")
  exit
end
