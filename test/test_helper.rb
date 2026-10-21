$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "date"
require "nfse_nacional"
require "minitest/autorun"
require "minitest/mock"
require_relative "support/test_certificate"

module NfseNacional
  # Relógio controlável para travel_to/travel (sem ActiveSupport).
  module TestClock
    def now = Thread.current[:nfse_nacional_now] || super
  end
  Time.singleton_class.prepend(TestClock)

  # Imita o pouco do ActiveSupport::TestCase que os testes copiados dos apps usam.
  class TestCase < Minitest::Test
    def self.test(name, &block)
      method = "test_#{name.gsub(/\s+/, "_")}"
      raise ArgumentError, "teste duplicado: #{name}" if method_defined?(method)

      define_method(method, &block)
    end

    def self.setup(&block) = define_method(:setup) { instance_exec(&block) }
    def self.teardown(&block) = define_method(:teardown) { instance_exec(&block) }

    def after_teardown
      Thread.current[:nfse_nacional_now] = nil
      super
    end

    alias_method :assert_not, :refute
    alias_method :assert_not_empty, :refute_empty
    alias_method :assert_not_equal, :refute_equal
    alias_method :assert_not_includes, :refute_includes

    def assert_nothing_raised = yield

    def travel_to(time)
      previous = Thread.current[:nfse_nacional_now]
      Thread.current[:nfse_nacional_now] = time
      yield
    ensure
      Thread.current[:nfse_nacional_now] = previous
    end

    # Como o ActiveSupport: dentro de um travel_to, avança o relógio parado.
    def travel(seconds) = Thread.current[:nfse_nacional_now] = Time.now + seconds

    def fixture_path(name) = File.expand_path("fixtures/#{name}", __dir__)
    def fixture(name) = File.read(fixture_path(name), encoding: "UTF-8")
  end
end
