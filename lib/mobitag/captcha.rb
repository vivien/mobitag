require 'RMagick'

# Boost RMagick classes
module Magick
  class Image
    def get_pixels_around(x, y, radius = 1)
      top_left_x = ((x - radius) <= 0) ? 0 : (x - radius)
      top_left_y = ((y - radius) <= 0) ? 0 : (y - radius)
      bottom_right_x = ((x + radius) >= self.columns - 1) ? self.columns - 1 : (x + radius)
      bottom_right_y = ((y + radius) >= self.rows - 1) ? self.rows - 1 : (y + radius)
      width = bottom_right_x - top_left_x + 1
      height = bottom_right_y - top_left_y + 1
      self.get_pixels(top_left_x, top_left_y, width, height)
    end

    def pixel_at(x, y)
      return nil if x < 0 || x >= self.columns
      return nil if y < 0 || y >= self.rows
      self.get_pixels(x, y, 1, 1).first
    end
  end

  class Pixel
=begin
    attr_accessor :row, :column

    def set_position(x, y)
      @column = x
      @row = y
    end
=end

    def white?
      self.to_color == 'white'
    end

    def black?
      self.to_color == 'black'
    end

    # Captcha letters are always brown red around 30000
    def brown?
      (20000..40000).include? self.red
    end
  end
end

module Mobitag
  class Captcha
    attr_reader :height, :width

    # Width => Number of chars
    NUMBER_OF_CHARS = {
      150 => 6,
      174 => 7,
      198 => 8,
      220 => 9
    }

    # Each letter has a fixed rotation
    ANGLES = [-3, -2, 10, -5, -3, 45, -5, 0, 10] # FIXME approximative

    def initialize(filename)
      @img = Magick::Image.read(filename).first
      @height = @img.rows
      @width = @img.columns
    end

    def expected_noc
      NUMBER_OF_CHARS[@width]
    end

    # Black on white image
    def extract_text
      img = Magick::Image.new(@width, @height)
      # Write brown pixels (i.e. text) only, in black
      @img.each_pixel do |pixel, x, y|
        if pixel.brown?
          img.pixel_color(x, y, 'black')
        end
      end
=begin or:
      img = @img.dup
      img.each_pixel do |pixel, x, y|
        color = (pixel.brown?) ? 'black' : 'white'
        img.pixel_color(x, y, color)
      end
=end
    img
    end
    def extract_text!
      @img = self.extract_text
    end

    # Reduce noise (white pixel in chars)
    def reduce_noise
      img = @img.dup
      img.each_pixel do |pixel, x, y|
        if pixel.white?
          neighbors = img.get_pixels_around(x, y).reject { |pixel| pixel.white? }
          if neighbors.count >= 7
            img.pixel_color(x, y, 'black') # Fix noise
          end
        end
      end
      img
    end
    def reduce_noise!
      @img = self.reduce_noise
    end

    def write(filename)
      @img.write(filename)
    end

    # Split each blocks
=begin
    # => [[[x1,y1], [x2,y2]], [[x1,y1], [x2,y2]]]
    def split
      blocks = []
      proximity = 2
      # for each pixel in the binary image
      @img.each_pixel do |pixel, x, y|
        # if the pixel is on
        if pixel.black?
          included = false
          x_range = ((x - proximity)..(x + proximity))
          y_range = ((y - proximity)..(y + proximity))
          # if any pixel we have seen before is next to it
          blocks.each do |block|
            block.each do |p|
              if x_range.include?(p.first) && y_range.include?(p.last)
                included = true
                # add to the same set
                block << [x, y]
                break
              end
            end
            break if included
          end
          # else, add to a new set
          blocks << [[x, y]] unless included
        end
      end
      blocks
    end
=end

    # Labeling of connected components
    # http://sebastien.mavromatis.free.fr/dl/AI_2_niveaux_gris.pdf p. 35
    def label_areas
      map = Matrix.new(@width, @height)
      area_number = 0
      equivalences = {}

      self.each_pixels do |pixel, x, y|
        if pixel.black?
          above = map[x, y - 1] rescue nil
          left = map[x - 1, y] rescue nil
          if (above.nil? && !left.nil?) || (!above.nil? && left.nil?)
            # only one of above and left neighbors has a label
            map[x, y] = above || left
          elsif !above.nil? && above == left
            # the two neighbors have the same label
            map[x, y] = above
          elsif !above.nil? && !left.nil? && above != left
            # the two neighbors have different labels
            min, max = [above, left].min, [above, left].max
            map[x, y] = min
            equivalences[max] = min
          else
            area_number += 1
            map[x, y] = area_number
          end
        end
      end

      puts "#{area_number} areas"
      puts "but there's #{equivalences.keys.size} equivalences"
      puts "restoring..."

      # Adjust neighbors which have different labels
      map.each do |area, x, y|
        unless area.nil?
          good = area
          i = 0
          while equivalences.key? good
            good = equivalences[good]
            puts "#{' ' * i}recursively found #{good}"
            i += 1
          end
          map[x, y] = equivalences[area] || area
        end
      end

      components = []

      map.each do |area, x, y|
        unless area.nil?
          components[area - 1] ||= Magick::Image.new(@width, @height)
          components[area - 1].pixel_color(x, y, 'black')
        end
      end

      puts "found #{components.size} components"

      #components
      components.each_with_index { |img, i| img.write("#{i}.jpg") } # TODO remove, for testing
    end

  # Left to right, up to down pixels iteration
  def each_pixels
    @height.times do |y|
      @width.times do |x|
        yield @img.pixel_at(x, y), x, y
      end
    end
  end

  # Colorize the erased line
  # Colorize a white pixel if the pixels above and under it are black
  def fix_line
    img = @img.dup
    self.each_pixels do |pixel, x, y|
      if pixel.white?
        above = img.pixel_at(x, y - 1)
        under = img.pixel_at(x, y + 1)
        next if above.nil? || under.nil?
        if above.black? && under.black?
          img.pixel_color(x, y, 'black')
        end
      end
    end
    img
  end
  def fix_line!
    @img = self.fix_line
  end

  class Matrix
    class OutOfBoundsError < StandardError; end

    attr_accessor :width, :height

    def initialize(x, y, val = nil)
      @width = x
      @height = y
      @map = Array.new
      @height.times { |y| @map << Array.new(@width, val) }
    end

    def get(x, y)
      raise OutOfBoundsError if out_of_bounds? x, y
      @map[y][x]
    end
    alias [] get

    def set(x, y, value)
      raise OutOfBoundsError if out_of_bounds? x, y
      @map[y][x] = value
    end
    alias []= set

    def each
      height.times do |y|
        width.times do |x|
          yield get(x, y), x, y
        end
      end
    end

    private

    def out_of_bounds?(x, y)
      !(0...width).include?(x) || !(0...height).include?(y)
    end
  end
end
end
