defmodule TaamolWeb.SiteSettingsLiveTest do
  # not async: site settings are cached globally (persistent_term)
  use TaamolWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Settings
  alias Taamol.Events.Hijri

  setup do
    Settings.reset_cache()
    on_exit(&Settings.reset_cache/0)
  end

  test "admins change the Hijri adjustment and prayer method", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Taamol.Repo.update!()
    before = Hijri.to_date(1448, 1, 10)

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/dashboard/settings")

    view
    |> form("#site-settings-form",
      site_setting: %{hijri_adjustment_days: "1", prayer_method: "Jafari"}
    )
    |> render_submit()

    assert Settings.get(:prayer_method) == "Jafari"
    assert Hijri.to_date(1448, 1, 10) == Date.add(before, 1)
  end

  test "rejects out-of-range values and non-admins" do
    user = user_fixture()
    scope = Taamol.Accounts.Scope.for_user(user)
    assert {:error, :forbidden} = Settings.update(scope, %{"hijri_adjustment_days" => 1})

    admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Taamol.Repo.update!()
    admin_scope = Taamol.Accounts.Scope.for_user(admin)
    assert {:error, changeset} = Settings.update(admin_scope, %{"hijri_adjustment_days" => 5})
    assert %{hijri_adjustment_days: [_]} = Taamol.DataCase.errors_on(changeset)
  end
end
