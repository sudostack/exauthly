defmodule Newline.EmailTest do
  use ExUnit.Case, async: true
  use Bamboo.Test

  import Newline.Email
  import Newline.Factory

  describe "password_reset_request/1" do
    test "gets sent from configured user" do
      user = build(:user)
      email = send_password_reset_request_email(user)
      assert email.from == {nil, "postmaster@newline.co"}
    end

    test "body exists" do
      user = build(:user)
      email = send_password_reset_request_email(user)
      assert email.html_body =~ "You recently requested a password reset"
    end
  end
end
