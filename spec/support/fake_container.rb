# frozen_string_literal: true

class FakeContainer
  def initialize(map = {})
    @map = map
  end

  def resolve(key)
    @map.fetch(key)
  end

  def registered?(key)
    @map.key?(key)
  end
end
