defmodule TrifleApp.Gettext do
  @moduledoc """
  A module providing Internationalization for the TrifleApp application.
  """

  use Gettext.Backend, otp_app: :trifle
end
