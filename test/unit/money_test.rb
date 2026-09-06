# frozen_string_literal: true

require_relative "../test_helper"

class MoneyTest < Minitest::Test
  def test_stores_exact_minor_units_and_normalizes_currency
    money = RubyRouting::Money.new(10_005, " rub ")

    assert_equal 10_005, money.amount_minor
    assert_equal "RUB", money.currency
    assert money.frozen?
    assert money.currency.frozen?
  end

  def test_supports_zero_without_introducing_fractional_arithmetic
    money = RubyRouting::Money.new(0, "USD")

    assert money.zero?
    assert_equal RubyRouting::Money.new(0, "USD"), money
  end

  def test_rejects_non_integral_or_negative_amounts
    assert_raises(ArgumentError) { RubyRouting::Money.new(10.5, "USD") }
    assert_raises(ArgumentError) { RubyRouting::Money.new("100", "USD") }
    assert_raises(ArgumentError) { RubyRouting::Money.new(-1, "USD") }
  end

  def test_rejects_missing_or_malformed_currency
    assert_raises(ArgumentError) { RubyRouting::Money.new(100, nil) }
    assert_raises(ArgumentError) { RubyRouting::Money.new(100, "US") }
    assert_raises(ArgumentError) { RubyRouting::Money.new(100, "US$") }
  end

  def test_addition_and_subtraction_are_exact_and_currency_safe
    left = RubyRouting::Money.new(10_000, "RUB")
    right = RubyRouting::Money.new(5, "rub")

    assert_equal RubyRouting::Money.new(10_005, "RUB"), left + right
    assert_equal RubyRouting::Money.new(9_995, "RUB"), left - right
    assert_raises(ArgumentError) { left + RubyRouting::Money.new(1, "USD") }
    assert_raises(ArgumentError) { right - RubyRouting::Money.new(6, "RUB") }
  end

  def test_money_values_have_value_equality
    values = {
      RubyRouting::Money.new(123, "USD") => :same_value
    }

    assert_equal :same_value, values[RubyRouting::Money.new(123, "usd")]
    refute_equal RubyRouting::Money.new(123, "USD"), RubyRouting::Money.new(124, "USD")
  end
end
