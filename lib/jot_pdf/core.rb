# frozen_string_literal: true

require "docile"

module JotPDF
  module Core
    class CrossReferenceTableEntry < Data.define(:offset, :generation, :usage)
    end

    # separating definition for steep
    class CrossReferenceTableEntry
      def self.default
        CrossReferenceTableEntry.new(
          offset: 0,
          generation: 65_535,
          usage: :free,
        )
      end
    end

    class ObjectRef < Data.define(:number, :generation)
    end

    class Writer
      attr_reader :objects, :io, :offset

      def initialize(io)
        @objects = [
          CrossReferenceTableEntry.default,
        ]
        @section = [0]
        @io = io
        @offset = 0
      end

      def new_object
        number = @objects.size
        @objects << CrossReferenceTableEntry.default
        ObjectRef.new(number:, generation: 0)
      end

      def update_object_entry(object_ref)
        @section << object_ref.number
        @objects[object_ref.number] = CrossReferenceTableEntry.new(
          generation: object_ref.generation,
          offset: @offset,
          usage: :in_use,
        )
      end

      def finish_section
        result = @section.dup
        @section.clear
        result
      end

      def <<(data)
        s = data.to_s
        @io << s
        @offset += s.bytesize
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
        if block
          ObjectWriteContext.new(@writer).dsl(&block)
          @writer << "\n"
        else
          # TODO: Why does this need annotation?
          # @type var finalizer: ^() -> ObjectRef
          finalizer = proc { @writer << "\n" }
          ObjectInterm.new(writer: @writer, finalizer:)
        end
      end
    end

    class ContentStreamWriteContext < WriteContext
      def op(operator, &block)
        ObjectWriteContext.new(@writer).dsl(&block) if block
        @writer << " " << operator << "\n"
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

      def hexstr(value)
        @writer << " <" << value.to_s << ">"
      end

      def ref(object_ref)
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

    class ObjectInterm
      def initialize(writer:, finalizer:)
        @writer = writer
        @finalizer = finalizer
      end

      def of_name(name)
        @writer << " /#{name}"
        @finalizer.call
      end

      def of_int(i)
        @writer << " #{i}"
        @finalizer.call
      end

      def of_str(value)
        @writer << " (" << value.to_s << ")"
        @finalizer.call
      end

      def of_ref(object_ref)
        @writer << " #{object_ref.number} #{object_ref.generation} R"
        @finalizer.call
      end

      def of_dict(&block)
        @writer << " <<\n"
        DictionaryWriteContext.new(@writer).dsl(&block)
        @writer << ">>"
        @finalizer.call
      end

      def of_array(&block)
        @writer << " ["
        ObjectWriteContext.new(@writer).dsl(&block)
        @writer << " ]"
        @finalizer.call
      end
    end

    class DocumentContext < WriteContext
      def header(version = "1.4")
        @writer << "%PDF-#{version}\n"
        @writer << "%\xff\xff\xff\xff\n"
      end

      def alloc_obj
        @writer.new_object
      end

      def obj(object_ref = nil, &block)
        object_ref ||= @writer.new_object
        @writer.update_object_entry(object_ref)
        @writer << "#{object_ref.number} #{object_ref.generation} obj"
        if block
          ObjectWriteContext.new(@writer).dsl(&block)
          @writer << "\nendobj\n"
          object_ref
        else
          # TODO: Why does this need annotation?
          # @type var finalizer: ^() -> ObjectRef
          finalizer = proc { @writer << "\nendobj\n"; object_ref }
          ObjectInterm.new(writer: @writer, finalizer:)
        end
      end

      def xref
        @prev_xref_offset = @xref_offset
        @xref_offset = @writer.offset
        @writer << "xref\n"
        section_objs = @writer.finish_section
        section_objs.sort.slice_when { |prev, curr| curr != prev.next }.each do |subsection|
          @writer << "#{subsection.first} #{subsection.size}\n"
          subsection.each do |n|
            object = objects[n]
            u = object.usage == :in_use ? "n" : "f"
            # each entry ends with SP LF
            @writer << "#{object.offset.to_s.rjust(10, "0")} #{object.generation.to_s.rjust(5, "0")} #{u} \n"
          end
        end
      end

      def trailer(&block)
        @writer << "trailer\n<<\n"
        DictionaryWriteContext.new(@writer).dsl do
          entry("Size").of_int objects.size
          entry("Prev").of_int @prev_xref_offset if @prev_xref_offset
          dsl(&block)
        end
        @writer << ">>\n"
      end

      def startxref
        @writer << "startxref\n"
        @writer << @xref_offset.to_s
        @writer << "\n"
      end

      def eof
        @writer << "%%EOF\n"
      end

      def dsl(&block)
        Docile.dsl_eval(self, &block)
      end
    end

    def self.write(io, &block)
      Docile.dsl_eval(DocumentContext.new(Writer.new(io)), &block)
    end
  end
end
