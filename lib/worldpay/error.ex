defmodule Worldpay.Error do
  @moduledoc """
  Structured error returned from all Worldpay API calls.

  ## Fields

  - `:type` — error classification atom
  - `:status` — HTTP status code (`nil` for non-HTTP errors)
  - `:reason` — atom describing the failure
  - `:message` — human-readable description
  - `:raw` — raw API response body (map or string)
  - `:custom_code` — Worldpay `customCode` field
  - `:validation_errors` — list of field-level validation errors from the API
  """

  @type error_type ::
          :http_error
          | :api_error
          | :timeout
          | :network_error
          | :circuit_open
          | :decode_error
          | :configuration_error

  @type t :: %__MODULE__{
          type: error_type() | nil,
          status: non_neg_integer() | nil,
          reason: atom() | nil,
          message: String.t() | nil,
          raw: map() | String.t() | nil,
          custom_code: String.t() | nil,
          validation_errors: [map()] | nil
        }

  defexception [:type, :status, :reason, :message, :raw, :custom_code, :validation_errors]

  @impl Exception
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: m}) when is_binary(m), do: m
  def message(%__MODULE__{reason: r}) when not is_nil(r), do: "Worldpay error: #{r}"
  def message(%__MODULE__{}), do: "Worldpay error"

  @doc "Build from a raw Worldpay JSON error body."
  @spec from_response(pos_integer(), %{String.t() => term()} | String.t()) :: t()
  def from_response(status, body) when is_map(body) do
    %__MODULE__{
      type: classify_status(status),
      status: status,
      reason: body_reason(body),
      message: body["message"],
      custom_code: body["customCode"],
      validation_errors: body["validationErrors"],
      raw: body
    }
  end

  def from_response(status, body) when is_binary(body) or is_nil(body) do
    %__MODULE__{
      type: :http_error,
      status: status,
      reason: :unexpected_response,
      message: "HTTP #{status}",
      raw: body
    }
  end

  @doc "Build from a network / transport error."
  @spec from_exception(struct() | term()) :: t()
  def from_exception(%{reason: :timeout}) do
    %__MODULE__{type: :timeout, reason: :timeout, message: "Request timed out"}
  end

  def from_exception(ex) when is_exception(ex) do
    %__MODULE__{
      type: :network_error,
      reason: :network_error,
      message: Exception.message(ex)
    }
  end

  def from_exception(ex) do
    %__MODULE__{
      type: :network_error,
      reason: :network_error,
      message: inspect(ex)
    }
  end

  # ── private ─────────────────────────────────────────────────────────────

  # classify_status/1 — only called with HTTP status codes (100–599).
  # Returns :api_error for 4xx, :http_error for everything else.
  @spec classify_status(pos_integer()) :: :api_error | :http_error
  defp classify_status(s) when s in 400..499, do: :api_error
  defp classify_status(_s), do: :http_error

  @spec body_reason(%{String.t() => term()}) :: atom()
  defp body_reason(%{"customCode" => code}) when is_binary(code) do
    # Input is already a Worldpay API constant — limited character set, safe to intern.
    code
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :api_error
  end

  defp body_reason(_body), do: :api_error
end
