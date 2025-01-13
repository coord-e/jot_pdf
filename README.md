# JotPDF

Streaming PDF writer DSL for Ruby. Check out a live-editing demo with ruby.wasm: https://jotpdf.coord-e.dev/

## Status

JotPDF is in its early stages, and the API is fairly unstable.

## Usage

```ruby
# Gemfile
gem 'jot_pdf'
```

JotPDF offers two types of DSLs. One is `JotPDF::Core`, a low-level API that directly exposes the structure of PDFs. The other is `JotPDF::Document`, a relatively high-level API built on top of `JotPDF::Core`, designed to be useful for actual document generation.

### JotPDF::Core

A PDF consists of a header, object definitions, `xref` (cross-reference table), and a trailer (including `trailer`, `startxref`, and an EOF marker).

```ruby
require "jot_pdf"

JotPDF::Core.write($stdout) do
  header

  # Emit your objects here

  xref
  trailer do
  end
  startxref
  eof
end
```

Use `obj` to define an object; it returns a reference to the object.

```ruby
require "jot_pdf"

JotPDF::Core.write($stdout) do
  header

  obj.of_dict do
    entry("Type").of_name "Pages"
    entry("Kids").of_array {}
    entry("Count").of_int 0
  end => pages_obj

  obj.of_dict do
    entry("Type").of_name "Catalog"
    entry("Pages").of_ref pages_obj
  end => catalog_obj

  xref
  trailer do
    entry("Size").of_int objects.size # you can access all declared objects via `objects`
    entry("Root").of_ref catalog_obj
  end
  startxref
  eof
end
```

Use `alloc_obj` to declare an object and emit its contents later.

```ruby
require "jot_pdf"

JotPDF::Core.write($stdout) do
  header

  alloc_obj => pages_obj

  obj.of_dict do
    entry("Type").of_name "Catalog"
    entry("Pages").of_ref pages_obj
  end => catalog_obj

  obj(pages_obj).of_dict do
    entry("Type").of_name "Pages"
    entry("Kids").of_array {}
    entry("Count").of_int 0
  end

  xref
  trailer do
    entry("Size").of_int objects.size
    entry("Root").of_ref catalog_obj
  end
  startxref
  eof
end
```

### JotPDF::Document

Use `page` to emit a page.

```ruby
require "jot_pdf"

JotPDF::Document.write($stdout) do
  page width: 210, height: 297 do
    text "Hello, World!", x: 10, y: 200
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/coord-e/jot_pdf. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/coord-e/jot_pdf/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the JotPDF project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/coord-e/jot_pdf/blob/master/CODE_OF_CONDUCT.md).
