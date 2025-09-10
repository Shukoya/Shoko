# frozen_string_literal: true

# Ensure our in-repo minimal Zip implementation is used when specs or
# code require 'zip'. This wrapper forwards to the library version.
require_relative 'lib/zip'
