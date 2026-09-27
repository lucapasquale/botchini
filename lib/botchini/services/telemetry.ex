defmodule Botchini.Services.Telemetry do
  @moduledoc """
  Req steps that emit a `[:botchini, :http, :request, :stop]` telemetry event for
  every external API call, tagged with the service, endpoint and response status
  """

  @spec attach(Req.Request.t(), atom()) :: Req.Request.t()
  def attach(req, service) do
    req
    |> Req.Request.put_private(:botchini_service, service)
    |> Req.Request.prepend_request_steps(botchini_telemetry_start: &put_start_time/1)
    |> Req.Request.append_response_steps(botchini_telemetry: &emit_response/1)
    |> Req.Request.append_error_steps(botchini_telemetry: &emit_error/1)
  end

  defp put_start_time(request) do
    Req.Request.put_private(request, :botchini_start_time, System.monotonic_time())
  end

  defp emit_response({request, response}) do
    emit(request, %{
      status: Integer.to_string(response.status),
      result: if(response.status < 400, do: :ok, else: :error)
    })

    {request, response}
  end

  # Transport failures (timeouts, DNS, connection refused) never get a status
  defp emit_error({request, exception}) do
    emit(request, %{status: "transport_error", result: :error})

    {request, exception}
  end

  defp emit(request, metadata) do
    start_time = Req.Request.get_private(request, :botchini_start_time, System.monotonic_time())

    :telemetry.execute(
      [:botchini, :http, :request, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{
        service: Req.Request.get_private(request, :botchini_service),
        endpoint: request.url.path
      })
    )
  end
end
