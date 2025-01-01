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

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    class DictionaryWriteContext < WriteContext
      def entry(name, &block)
        @writer << "/#{name}"
        ObjectWriteContext.new(@writer).dsl(&block)
        @writer << "\n"
      end
    end

    class ContentStreamWriteContext < WriteContext
      def op(operator, &block)
        ObjectWriteContext.new(@writer).dsl(&block) if block
        @writer << operator << "\n"
      end
    end

    class ObjectWriteContext < WriteContext
      def name(name)
        @writer << " /#{name}"
      end

      def int(value)
        @writer << " " << value.to_s
      end

      def str(value)
        @writer << " (" << value.to_s << ")"
      end

      def ref(name)
        object_ref = @writer.ensure_object(name)
        @writer << " #{object_ref.number} #{object_ref.generation} R"
      end

      def array(&block)
        @writer << " ["
        ObjectWriteContext.new(@writer).dsl(&block)
        @writer << "]"
      end

      def dict(&block)
        @writer << " <<\n"
        DictionaryWriteContext.new(@writer).dsl(&block)
        @writer << ">>"
      end

      def stream
        @writer << "\nstream\n"
        stream_start = @writer.offset
        yield @writer
        stream_size = @writer.offset - stream_start
        @writer << "endstream"
        stream_size
      end

      def content_stream(&block)
        stream do |w|
          ContentStreamWriteContext.new(w).dsl(&block)
        end
      end
    end

    class PDFWriteContext < WriteContext
      def header(version = "1.3")
        @writer << "%PDF-#{version}\n"
      end

      def obj(name, generation: 0, &block)
        object_ref = @writer.ensure_object(name, generation:)
        @writer.update_object_entry(object_ref)
        @writer << "#{object_ref.number} #{object_ref.generation} obj"
        ObjectWriteContext.new(@writer).dsl(&block)
        @writer << "\nendobj\n"
      end

      def xref
        @xref_offset = @writer.offset
        @writer << "xref\n"
        @writer << "0 #{objects.size}\n"
        objects.each do |object|
          u = object.usage == :in_use ? "n" : "f"
          @writer << "#{object.offset.to_s.rjust(10, "0")} #{object.generation.to_s.rjust(5, "0")} #{u}\n"
        end
      end

      def trailer(&block)
        @writer << "trailer\n<<\n"
        DictionaryWriteContext.new(@writer).dsl(&block)
        @writer << ">>\n"
      end

      def startxref
        @writer << "startxref\n"
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
