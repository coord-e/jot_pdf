require 'docile'

module PDFWrite
  module Core
    CrossReferenceTableEntry = Data.define(:offset, :generation, :usage) do
      def self.default
        CrossReferenceTableEntry.new(
          offset: 0,
          generation: 65535,
          usage: :free,
        )
      end
    end

    ObjectRef = Data.define(:number, :generation)

    class Writer
      attr_reader :objects, :io, :offset

      def initialize(io)
        @objects = [
          CrossReferenceTableEntry.default,
        ]
        @object_names = {}
        @io = io
        @offset = 0
      end

      def ensure_object(name, generation: 0)
        if number = @object_names[name]
          ObjectRef.new(number:, generation:)
        else
          number = @objects.size
          @objects << CrossReferenceTableEntry.default
          @object_names[name] = number
          ObjectRef.new(number:, generation:)
        end
      end

      def update_object_entry(object_ref)
        @objects[object_ref.number] = CrossReferenceTableEntry.new(
          generation: object_ref.generation,
          offset: @offset,
          usage: :in_use,
        )
      end

      def <<(data)
        @io << data
        @offset += data.bytesize
        self
      end
    end

    class WriteContext
      def initialize(writer)
        @writer = writer
      end

      def objects
        @writer.objects
      end
    end

    class DictionaryWriteContext < WriteContext
      def write_entry(name, &block)
        @writer << "/#{name} "
        Docile.dsl_eval(ObjectWriteContext.new(@writer), &block)
        @writer << "\n"
      end
    end

    class ArrayWriteContext < WriteContext
      def write_element(&block)
        Docile.dsl_eval(ObjectWriteContext.new(@writer), &block)
        @writer << " "
      end
    end

    class StreamWriteContext < WriteContext
      def write_begin_text
        @writer << "BT\n"
      end

      def write_text_font(font_name, size)
        @writer << "/#{font_name} #{size} Tf\n"
      end

      def write_text_destination(x, y)
        @writer << "#{x} #{y} Td\n"
      end

      def write_text(text)
        @writer << "(#{text}) Tj\n"
      end

      def write_end_text
        @writer << "ET\n"
      end

      def write_do(name)
        @writer << "/#{name} Do\n"
      end

      def write_bytes(data)
        @writer << data << "\n"
      end

      def write_cm(a, b, c, d, e, f)
        @writer << "#{a} #{b} #{c} #{d} #{e} #{f} cm\n"
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    class StreamObjectWriteContext < DictionaryWriteContext
      def stream(&block)
        @writer << ">>\nstream\n"
        stream_start = @writer.offset
        Docile.dsl_eval(StreamWriteContext.new(@writer), &block)
        stream_size = @writer.offset - stream_start
        @writer << "endstream"
        stream_size
      end
    end

    class ObjectWriteContext < WriteContext
      def write_name(name)
        @writer << "/#{name}"
      end

      def write_integer(value)
        @writer << value.to_s
      end

      def write_object_ref(name)
        object_ref = @writer.ensure_object(name)
        @writer << "#{object_ref.number} #{object_ref.generation} R"
      end

      def write_array(&block)
        @writer << "["
        Docile.dsl_eval(ArrayWriteContext.new(@writer), &block)
        @writer << "]"
      end

      def write_dictionary(&block)
        @writer << "<<\n"
        Docile.dsl_eval(DictionaryWriteContext.new(@writer), &block)
        @writer << ">>"
      end

      def write_stream(&block)
        @writer << "<<\n"
        Docile.dsl_eval(StreamObjectWriteContext.new(@writer), &block)
      end
    end

    class PDFWriteContext < WriteContext
      def write_header(version = "1.3")
        @writer << "%PDF-#{version}\n"
      end

      def write_object(name, generation: 0, &block)
        object_ref = @writer.ensure_object(name, generation:)
        @writer.update_object_entry(object_ref)
        @writer << "#{object_ref.number} #{object_ref.generation} obj\n"
        Docile.dsl_eval(ObjectWriteContext.new(@writer), &block)
        @writer << "\nendobj\n"
      end

      def write_cross_reference_table
        @xref_offset = @writer.offset
        @writer << "xref\n"
        @writer << "0 #{objects.size}\n"
        objects.each do |object|
          u = object.usage == :in_use ? "n" : "f"
          @writer << "#{object.offset.to_s.rjust(10, "0")} #{object.generation.to_s.rjust(5, "0")} #{u}\n"
        end
      end

      def write_trailer(&block)
        @writer << "trailer\n<<\n"
        Docile.dsl_eval(DictionaryWriteContext.new(@writer), &block)
        @writer << ">>\nstartxref\n"
        @writer << @xref_offset.to_s
        @writer << "\n"
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    def self.write(io, &block)
      Docile.dsl_eval(PDFWriteContext.new(Writer.new(io)), &block)
    end
  end
end
