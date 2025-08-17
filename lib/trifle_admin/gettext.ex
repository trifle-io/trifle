defmodule TrifleAdmin.Gettext do
  @moduledoc """
  A module providing Internationalization for the TrifleAdmin application.
  """

  use Gettext.Backend, otp_app: :trifle
end