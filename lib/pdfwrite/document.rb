# frozen_string_literal: true

module PDFWrite
  module Document
    class PageContext
      attr_reader :used_fonts

      def initialize(ctx, default_font:)
        @ctx = ctx
        @default_font = default_font
        @used_fonts = Set.new
      end

      def color(r:, g:, b:)
        @ctx.dsl do
          op("rg") { int r; int g; int b }
        end
      end

      def stroke_color(r:, g:, b:)
        @ctx.dsl do
          op("RG") { int r; int g; int b }
        end
      end

      def rect(x:, y:, width:, height:)
        @ctx.dsl do
          op("re") { int x; int y; int width; int height }
        end
      end

      def strike
        @ctx.dsl do
          op("s")
        end
      end

      def fill
        @ctx.dsl do
          op("f")
        end
      end

      def text(text, x: 0, y: 0, size: 15, font: nil)
        font ||= @default_font
        @used_fonts << font
        @ctx.dsl do
          text.each_line(chomp: true).with_index do |l, idx|
            op("BT")
            op("Tf") { name font; int size }
            op("Td") { int x; int(y - size * idx) }
            op("Tj") { str l }
            op("ET")
          end
        end
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    class DocumentWriter
      attr_reader :pages, :used_fonts

      def initialize(core, resources_obj:, pages_obj:)
        @core = core
        @pages = []
        @pages_obj = pages_obj
        @resources_obj = resources_obj
        @default_font = nil

        @used_fonts = Set.new
      end

      def default_font(name)
        @default_font = name
      end

      def page(width:, height:, &block)
        @core.dsl do
          alloc_obj => length_obj

          stream_size = nil
          obj do
            dict { entry("Length") { ref length_obj } }
            content_stream do
              page_ctx = PageContext.new(self, default_font: @default_font)
              page_ctx.dsl(&block)
              @used_fonts.merge(page_ctx.used_fonts)
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
    end

    def self.write(io, &block)
      Core.write(io) do
        header

        alloc_obj => resources_obj
        alloc_obj => pages_obj
        writer = Document::DocumentWriter.new(self, resources_obj:, pages_obj:)
        writer.instance_exec(&block)

        obj(resources_obj).of_dict do
          entry("Font").of_dict do
            writer.used_fonts.each do |n|
              entry(n).of_dict do
                entry("Type") { name "Font" }
                entry("Subtype") { name "Type1" }
                entry("BaseFont") { name n }
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
      end
    end
  end
end
