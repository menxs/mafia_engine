defmodule MafiaEngine.Role do
  @moduledoc """
  This module defines the type for role.
  """

  @typedoc """
    The possible roles aplayer can have.
  """
  @type t :: :townie | :mafioso | :sheriff | :doctor | :unknown

  @typedoc """
    The possible outcomes resulting of role interactions during the night phase.
  """
  @type outcome :: :kill | :investigate | :heal
end