# frozen_string_literal: true

require "pdf/reader"

RSpec.describe PDFWrite::Document do
  it "writes a page with text" do
    io = StringIO.new
    PDFWrite::Document.write(io) do
      page width: 100, height: 100 do
        text "test"
      end
    end

    reader = PDF::Reader.new(io)
    expect(reader.pages.size).to be 1
    expect(reader.pages[0].text).to eq "test"
  end
end
