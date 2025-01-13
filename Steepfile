# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"
  configure_code_diagnostics(D::Ruby.default)
  # TODO: How to type instance variables inside the DSL?
  # configure_code_diagnostics(D::Ruby.strict)
end
