# frozen_string_literal: true

module SpecEnvHelpers
  def with_env(vars)
    previous = {}
    vars.each do |key, value|
      previous[key] = ENV.key?(key) ? ENV[key] : :__missing__
      ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      if value == :__missing__
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
