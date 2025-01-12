# frozen_string_literal: true

require "pdf/reader"
require "pdf/inspector"

RSpec.describe PDFWrite::Document do
  it "writes a page with text" do
    io = StringIO.new
    PDFWrite::Document.write(io) do
      page width: 100, height: 200 do
        text "test"
      end
    end

    reader = PDF::Reader.new(io)
    expect(reader.pages.size).to be 1
    expect(reader.pages[0].width).to eq 100
    expect(reader.pages[0].height).to eq 200
    expect(reader.pages[0].text).to eq "test"
  end

  it "writes many pages" do
    io = StringIO.new
    PDFWrite::Document.write(io) do
      10.times do
        page width: 100, height: 200 do
          text "test"
        end
      end
    end

    reader = PDF::Reader.new(io)
    expect(reader.pages.size).to be 10
    reader.pages.each do |page|
      expect(page.width).to be 100
      expect(page.height).to be 200
      expect(page.text).to eq "test"
    end
  end

  it "embeds Japanese text within a page" do
    io = StringIO.new
    PDFWrite::Document.write(io) do
      load_font "spec/data/Mplus1-Regular.ttf"
      page width: 100, height: 200 do
        text "こんにちは", font: "MPLUS1-Regular"
      end
    end

    reader = PDF::Reader.new(io)
    expect(reader.pages.size).to be 1
    expect(reader.pages[0].width).to eq 100
    expect(reader.pages[0].height).to eq 200
    expect(reader.pages[0].text).to eq "こんにちは"
  end

  it "strokes a line" do
    io = StringIO.new
    PDFWrite::Document.write(io) do
      page width: 100, height: 200 do
        path [0, 0], [10, 20]
        stroke
      end
    end

    line_drawing = PDF::Inspector::Graphics::Line.analyze(io)
    expect(line_drawing.points).to eq([[0, 0], [10, 20]])
  end

  it "strokes a rectangle" do
    io = StringIO.new
    PDFWrite::Document.write(io) do
      page width: 100, height: 200 do
        rect x: 10, y: 20, width: 50, height: 60
        stroke
      end
    end

    rects = PDF::Inspector::Graphics::Rectangle.analyze(io).rectangles
    expect(rects[0][:point]).to eq([10, 20])
    expect(rects[0][:width]).to eq(50)
    expect(rects[0][:height]).to eq(60)
  end
end
