defmodule Taamol.Accounts.AuthorizationTest do
  use Taamol.DataCase

  import Taamol.AccountsFixtures

  alias Taamol.Accounts
  alias Taamol.Accounts.Scope

  test "only a confirmed account can bootstrap the first admin" do
    unconfirmed = unconfirmed_user_fixture()
    assert {:error, :user_not_found} = Accounts.bootstrap_admin("missing@example.com")
    assert {:error, :user_unconfirmed} = Accounts.bootstrap_admin(unconfirmed.email)

    user = user_fixture()
    assert {:ok, admin} = Accounts.bootstrap_admin(user.email)
    assert Accounts.admin?(Scope.for_user(admin))
    assert Accounts.allowed?(Scope.for_user(admin), :view_dashboard)
    assert {:error, :admin_already_exists} = Accounts.bootstrap_admin(unconfirmed.email)
  end

  test "registration cannot assign roles or permissions" do
    attrs = valid_user_attributes() |> Map.merge(%{role: :admin, can_view_dashboard: true})
    assert {:ok, user} = Accounts.register_user(attrs)
    assert user.role == :user
    refute user.can_view_dashboard
    refute Accounts.allowed?(Scope.for_user(user), :view_dashboard)
  end
end
