defmodule Worldpay.ErrorTest do
  use ExUnit.Case, async: true

  alias Worldpay.Error

  describe "from_response/2" do
    test "parses a 400 API error body" do
      body = %{
        "customCode" => "BAD_REQUEST",
        "message" => "Invalid card number",
        "validationErrors" => [%{"field" => "cardNumber", "message" => "invalid"}]
      }

      error = Error.from_response(400, body)

      assert error.type == :api_error
      assert error.status == 400
      assert error.message == "Invalid card number"
      assert error.custom_code == "BAD_REQUEST"
      assert length(error.validation_errors) == 1
    end

    test "handles 500 errors" do
      error = Error.from_response(500, %{"message" => "Internal error"})
      assert error.type == :http_error
      assert error.status == 500
    end

    test "handles non-map body gracefully" do
      error = Error.from_response(503, "Service Unavailable")
      assert error.type == :http_error
      assert error.raw == "Service Unavailable"
    end
  end

  describe "message/1" do
    test "returns the message field when set" do
      error = %Error{message: "Something went wrong"}
      assert Exception.message(error) == "Something went wrong"
    end

    test "falls back to reason atom" do
      error = %Error{reason: :timeout}
      assert Exception.message(error) =~ "timeout"
    end
  end
end
