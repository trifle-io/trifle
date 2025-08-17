defmodule TrifleApi.Gettext do
  @moduledoc """
  A module providing Internationalization for the TrifleApi application.
  """

  use Gettext.Backend, otp_app: :trifle
end