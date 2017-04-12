defmodule Newline.Factory do
  use ExMachina.Ecto, repo: Newline.Repo
  import Comeonin.Bcrypt, only: [hashpwsalt: 1]

  @pass "Something"
  @encrypted_password hashpwsalt(@pass)

  def user_factory do
    %Newline.User{
      first_name: "Ari",
      last_name: "Lerner",
      email: sequence(:email, &"email-#{&1}@fullstack.io"),
      password: @pass,
      encrypted_password: @encrypted_password
    }
  end

end