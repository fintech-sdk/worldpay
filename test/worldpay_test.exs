defmodule WorldpayTest do
  use ExUnit.Case, async: true
  doctest Worldpay

  test "greets the world" do
    assert Worldpay.hello() == :world
  end
end
