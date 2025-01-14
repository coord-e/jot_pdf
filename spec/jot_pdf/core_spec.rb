# frozen_string_literal: true

require "pdf/reader"

RSpec.describe JotPDF::Core do
  it "writes a valid header and trailer" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header
      xref
      trailer {}
    end

    expect { PDF::Reader.new(io) }.not_to raise_error
  end

  it "writes a boolean object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_bool true

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to be true
  end

  it "writes a numeric object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_num 1

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to be 1
  end

  it "writes a string object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_str "string"

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to eq("string")
  end

  it "writes a hexadecimal string object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_hexstr "010203"

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to eq("\x01\x02\x03")
  end

  it "writes a name object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_name "Name"

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to eq(:Name)
  end

  it "writes an array object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_array { name "Name"; num 1 }

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to eq([:Name, 1])
  end

  it "writes a dictionary object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_dict do
        entry("Type").of_name "Catalog"
      end

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to eq({ Type: :Catalog })
  end

  it "writes a stream object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj do
        dict do
          entry("Length").of_num 7
        end
        stream do |w|
          w << "content"
        end
      end

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first.hash).to eq({ Length: 7 })
    expect(pdf.objects.values.first.data).to eq("content")
  end

  it "writes a content stream object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj do
        dict do
          entry("Length").of_num 29
        end
        content_stream do
          op("BT")
          op("Td") { num 10; num 20 }
          op("Tj") { str "text" }
          op("ET")
        end
      end

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first.hash).to eq({ Length: 29 })
    expect(pdf.objects.values.first.data.split).to eq(["BT", "10", "20", "Td", "(text)", "Tj", "ET"])
  end

  it "writes a null object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj.of_null

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values.first).to be nil
  end

  it "writes an indirect object" do
    io = StringIO.new
    JotPDF::Core.write(io) do
      header

      obj1 = obj.of_bool true
      obj.of_ref obj1

      xref
      trailer {}
    end

    pdf = PDF::Reader.new(io)
    expect(pdf.objects.values[1]).to eq(pdf.objects.keys[0])
  end
end
