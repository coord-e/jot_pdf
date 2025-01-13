# frozen_string_literal: true

require "ttfunk"
require "ttfunk/subset"

module JotPDF
  module Document
    class StandardFont
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def unicode_to_code(codepoint)
        raise if codepoint > 255

        codepoint
      end

      def use(text)
        text.each_codepoint.map { |c| format("%02x", unicode_to_code(c)) }.join
      end
    end

    class NonstandardFont
      attr_reader :subset

      def initialize(font)
        @subset = TTFunk::Subset.for(font, :unicode_8bit)
      end

      def name
        @subset.original.name.postscript_name
      end

      def unicode_to_code(codepoint)
        @subset.from_unicode(codepoint)
      end

      def use(text)
        text.each_codepoint.map { |c| @subset.use(c); format("%02x", unicode_to_code(c)) }.join
      end

      def encode_subset
        @subset.encode
      end
    end

    class FontManager
      attr_writer :default_font

      def initialize(default_font:)
        @fonts = {}
        @default_font = default_font
      end

      def load_font(path)
        font = TTFunk::File.open(path)
        name = font.name.postscript_name
        @fonts[name] = NonstandardFont.new(font)
      end

      def require(spec = nil)
        spec ||= @default_font
        if spec.is_a? Symbol
          @fonts[spec] ||= StandardFont.new(spec)
        else
          @fonts.fetch(spec)
        end
      end

      def loaded_fonts
        @fonts
      end
    end

    class PageContext
      def initialize(ctx, font_manager:)
        @ctx = ctx
        @font_manager = font_manager
      end

      def color(color = nil, r: nil, g: nil, b: nil)
        # rubocop:disable Style/RedundantCondition
        r, g, b =
          if color
            colorspec(color)
          else
            colorspec(r:, g:, b:)
          end
        # rubocop:enable Style/RedundantCondition
        @ctx.dsl do
          op("rg") { int r; int g; int b }
        end
      end

      def stroke_color(color = nil, r: nil, g: nil, b: nil)
        # rubocop:disable Style/RedundantCondition
        r, g, b =
          if color
            colorspec(color)
          else
            colorspec(r:, g:, b:)
          end
        # rubocop:enable Style/RedundantCondition
        @ctx.dsl do
          op("RG") { int r; int g; int b }
        end
      end

      def stroke_width(width)
        @ctx.dsl do
          op("w") { int width }
        end
      end

      def rect(x:, y:, width:, height:)
        @ctx.dsl do
          op("re") { int x; int y; int width; int height }
        end
      end

      def path(*args)
        @ctx.dsl do
          x0, y0 = args.shift
          op("m") { int x0; int y0 }
          args.each do |x, y|
            op("l") { int x; int y }
          end
          op("h")
        end
      end

      def stroke
        @ctx.dsl do
          op("s")
        end
      end

      def fill
        @ctx.dsl do
          op("f")
        end
      end

      def text(text = nil, **kwargs, &block)
        @ctx.dsl do
          op("BT")
          tc = TextContext.new(@ctx, font_manager: @font_manager, **kwargs)
          tc.show text if text
          tc.dsl(&block) if block
          op("ET")
        end
      end

      def image(n, x:, y:, width:, height:)
        @ctx.dsl do
          op("cm") { int width; int 0; int 0; int height; int x; int y }
          op("Do") { name n }
        end
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end

      private

      def colorspec(color = nil, r: nil, g: nil, b: nil)
        r ||= 0.0
        g ||= 0.0
        b ||= 0.0

        if color
          b = (color & 0xff).to_f
          g = ((color >> 8) & 0xff).to_f
          r = ((color >> 16) & 0xff).to_f
        end

        r /= 256.0 if r > 1
        g /= 256.0 if g > 1
        b /= 256.0 if b > 1

        [r, g, b]
      end
    end

    class TextContext < PageContext
      undef_method :text

      attr_reader :base_x, :base_y

      def initialize(ctx, font_manager:, x: 0.0, y: 0.0, font: nil, size: nil, line_height: nil)
        super(ctx, font_manager:)
        @base_x = 0.0
        @base_y = 0.0
        move(x:, y:)
        font(font, **{ size: }.compact)
        @line_height = line_height
      end

      def font(spec, size: nil)
        @font = @font_manager.require(spec)
        size ||= @size
        @size ||= size
        @ctx.dsl do
          op("Tf") { name @font.name; int(size || 15) }
        end
      end

      def move(x:, y:)
        @base_x += x
        @base_y += y
        @ctx.dsl do
          op("Td") { int x; int y }
        end
      end

      def linebreak(factor: 1.0)
        # @type var factor: ::Numeric
        move x: 0.0, y: -line_height * factor
      end

      def show(text)
        @ctx.dsl do
          text.each_line(chomp: true).with_index do |line, idx|
            # @type self: JotPDF::Core::ContentStreamWriteContext & TextContext
            move x: 0.0, y: -line_height unless idx.zero?
            op("Tj") { hexstr @font.use(line) }
          end
        end
      end

      private

      def line_height
        @line_height || @size
      end
    end

    class ImageContext
      attr_reader :image_obj

      def initialize(core, width:, height:)
        @core = core
        @width = width
        @height = height
        @mask_obj = core.alloc_obj
        @image_obj = core.alloc_obj
      end

      def alpha(&block)
        @core.dsl do
          alloc_obj => length_obj
          stream_size = nil
          obj(@mask_obj) do
            dict do
              entry("Type").of_name "XObject"
              entry("Subtype").of_name "Image"
              entry("Width").of_int @width
              entry("Height").of_int @height
              entry("ColorSpace").of_name "DeviceGray"
              entry("Decode").of_array { int 0; int 1 }
              entry("BitsPerComponent").of_int 8
              entry("Length").of_ref length_obj
            end
            stream(&block) => stream_size
          end
          obj(length_obj) { int stream_size }
        end
      end

      def rgb(&block)
        @core.dsl do
          alloc_obj => length_obj
          stream_size = nil
          obj(@image_obj) do
            dict do
              entry("Type").of_name "XObject"
              entry("Subtype").of_name "Image"
              entry("Width").of_int @width
              entry("Height").of_int @height
              entry("ColorSpace").of_name "DeviceRGB"
              entry("BitsPerComponent").of_int 8
              entry("SMask").of_ref @mask_obj
              entry("Length").of_ref length_obj
            end
            stream(&block) => stream_size
          end
          obj(length_obj) { int stream_size }
        end
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    class DocumentWriter
      attr_reader :pages, :images, :font_manager

      def initialize(core, resources_obj:, pages_obj:)
        @core = core
        @pages = []
        @pages_obj = pages_obj
        @resources_obj = resources_obj
        @images = {}
        @font_manager = FontManager.new(default_font: :Helvetica)
      end

      def default_font(spec)
        @font_manager.default_font = spec
      end

      def load_font(path)
        @font_manager.load_font(path)
      end

      def image(n, width:, height:, &block)
        ic = ImageContext.new(@core, width:, height:)
        ic.dsl(&block)
        @images[n] = ic.image_obj
      end

      def page(width:, height:, &block)
        @core.dsl do
          alloc_obj => length_obj

          stream_size = nil
          obj do
            dict { entry("Length") { ref length_obj } }
            content_stream do
              PageContext.new(self, font_manager: @font_manager).dsl(&block)
            end => stream_size
          end => contents_obj

          obj(length_obj) { int stream_size }

          obj.of_dict do
            entry("Type") { name "Page" }
            entry("Parent") { ref @pages_obj }
            entry("MediaBox").of_array { int 0; int 0; int width; int height }
            entry("Resources") { ref @resources_obj }
            entry("Contents") { ref contents_obj }
          end => page_obj
          @pages << page_obj
        end
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    def self.generate_unicode_cmap(mapping)
      <<~CMAP
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        /CIDSystemInfo 3 dict dup begin
          /Registry (Adobe) def
          /Ordering (UCS) def
          /Supplement 0 def
        end def
        /CMapName /Adobe-Identity-UCS def
        /CMapType 2 def

        1 begincodespacerange
        <00> <FF>
        endcodespacerange

        #{mapping.length} beginbfchar
        #{mapping.map do |code, codepoint|
            format("<%<code>02X><%<codepoint>s>", code:, codepoint: codepoint.chr(::Encoding::UTF_16BE).unpack1("H*"))
          end.join("\n")}
        endbfchar

        endcmap
        CMapName currentdict /CMap defineresource pop
        end
        end
      CMAP
    end

    def self.write(io, &block)
      Core.write(io) do
        header

        alloc_obj => resources_obj
        alloc_obj => pages_obj
        writer = Document::DocumentWriter.new(self, resources_obj:, pages_obj:)
        writer.dsl(&block)

        # @type var font_file_objs: Hash[::String | Symbol, ObjectRef]
        # @type var widths_objs: Hash[::String | Symbol, ObjectRef]
        # @type var tounicode_objs: Hash[::String | Symbol, ObjectRef]
        font_file_objs = {}
        widths_objs = {}
        tounicode_objs = {}
        writer.font_manager.loaded_fonts.each do |n, f|
          # TODO: How can Steep use is_a? on _Font?
          # rubocop:disable Style/CaseEquality
          next unless NonstandardFont === f
          # rubocop:enable Style/CaseEquality

          subset_data = f.encode_subset
          obj do
            dict do
              entry("Length").of_int subset_data.bytesize
              entry("Length1").of_int subset_data.bytesize # always required for TrueType
            end
            stream do |stream|
              stream << subset_data
            end
          end => font_file_obj
          font_file_objs[n] = font_file_obj

          subset = TTFunk::File.new(subset_data)
          obj.of_array do
            (subset.os2.first_char_index..subset.os2.last_char_index).each do |code|
              gid = subset.cmap.tables.first[code]
              width_in_units = subset.horizontal_metrics.for(gid).advance_width
              int (Float(width_in_units) * 1000 / subset.header.units_per_em).to_i
            end
          end => widths_obj
          widths_objs[n] = widths_obj

          alloc_obj => length_obj
          stream_size = nil
          obj do
            dict { entry("Length").of_ref length_obj }
            stream do |w|
              w << generate_unicode_cmap(f.subset.to_unicode_map)
            end => stream_size
          end => tounicode_obj
          obj(length_obj).of_int stream_size
          tounicode_objs[n] = tounicode_obj
        end

        obj(resources_obj).of_dict do
          entry("XObject").of_dict do
            writer.images.each do |n, r|
              entry(n).of_ref r
            end
          end
          entry("ProcSet").of_array { name "PDF"; name "Text"; name "ImageB"; name "ImageC"; name "ImageI" }
          entry("Font").of_dict do
            writer.font_manager.loaded_fonts.each do |n, f|
              entry(n.to_s).of_dict do
                entry("Type") { name "Font" }
                case f
                when StandardFont
                  entry("Subtype") { name "Type1" }
                  entry("BaseFont") { name n.to_s }
                when NonstandardFont
                  subset = TTFunk::File.new(f.encode_subset)
                  # https://github.com/prawnpdf/prawn/blob/aaea7f6beda092ba48001414125a576dcf891362/lib/prawn/fonts/ttf.rb#L446-L447
                  base_name = subset.name.postscript_name[0, 33].delete("\0")
                  entry("Subtype").of_name "TrueType"
                  entry("FirstChar").of_int subset.os2.first_char_index
                  entry("LastChar").of_int subset.os2.last_char_index
                  entry("ToUnicode").of_ref tounicode_objs[n]
                  entry("BaseFont").of_name base_name
                  entry("Widths").of_ref widths_objs[n]
                  entry("FontDescriptor").of_dict do
                    entry("Ascent").of_int subset.ascent
                    entry("Descent").of_int subset.descent
                    entry("CapHeight").of_int subset.os2.cap_height
                    entry("StemV").of_int 0
                    entry("ItalicAngle").of_int 0
                    entry("Flags").of_int 0b100
                    entry("FontBBox").of_array do
                      subset.bbox.each do |i|
                        int i
                      end
                    end
                    entry("FontName").of_name base_name
                    entry("XHeight").of_int subset.os2.x_height
                    entry("FontFile2").of_ref font_file_objs[n]
                  end
                end
              end
            end
          end
        end => resources_obj

        obj(pages_obj).of_dict do
          entry("Type") { name "Pages" }
          entry("Kids").of_array do
            writer.pages.each do |page|
              ref page
            end
          end
          entry("Count") { int writer.pages.size }
        end
        obj.of_dict do
          entry("Type") { name "Catalog" }
          entry("Pages") { ref pages_obj }
        end => root_obj
        xref
        trailer do
          entry("Size") { int objects.size }
          entry("Root") { ref root_obj }
        end
        startxref
        eof
      end
    end
  end
end
