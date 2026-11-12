defmodule TaamolWeb.GalleryLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.{Gallery, Repo}

  @png Path.expand("../../support/fixtures/cover.png", __DIR__)

  defp admin_fixture do
    user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!()
  end

  # inserts images one second apart so their order is predictable (newest last)
  defp images_fixture(admin, count) do
    base = DateTime.utc_now(:second)

    for i <- 1..count do
      {:ok, image} =
        Gallery.create_image(Scope.for_user(admin), "/uploads/test/#{i}.png", %{
          caption: "Photo #{i}"
        })

      image |> Ecto.Changeset.change(inserted_at: DateTime.add(base, i - count)) |> Repo.update!()
    end
  end

  describe "public gallery" do
    test "shows an empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gallery")
      assert has_element?(view, "#gallery-empty")
    end

    test "lays out the mosaic and opens the viewer", %{conn: conn} do
      [_, _, _, _, _, second_newest, newest] = images_fixture(admin_fixture(), 7)

      {:ok, view, _html} = live(conn, ~p"/gallery")
      # in each group of nine: 3rd and 6th tall, 4th wide, 7th large (2×2)
      shown = images_desc()
      assert has_element?(view, "#images-#{Enum.at(shown, 2).id}.row-span-2")
      assert has_element?(view, "#images-#{Enum.at(shown, 3).id}.col-span-2")
      assert has_element?(view, "#images-#{Enum.at(shown, 6).id}.col-span-2.row-span-2")
      refute has_element?(view, "#images-#{Enum.at(shown, 0).id}.row-span-2")

      view |> element("#images-#{newest.id}") |> render_click()
      assert_patch(view, ~p"/gallery?#{[photo: newest.id]}")
      assert has_element?(view, "#gallery-viewer img[src='#{newest.image_url}']")
      assert has_element?(view, "#viewer-caption", "Photo 7")
      refute has_element?(view, "#viewer-newer")

      render_keydown(view, "viewer-key", %{"key" => "ArrowRight"})
      assert_patch(view, ~p"/gallery?#{[photo: second_newest.id]}")

      render_keydown(view, "viewer-key", %{"key" => "Escape"})
      assert_patch(view, ~p"/gallery")
      refute has_element?(view, "#gallery-viewer")
    end

    test "loads more photos", %{conn: conn} do
      images = images_fixture(admin_fixture(), 19)
      oldest = hd(images)

      {:ok, view, _html} = live(conn, ~p"/gallery")
      refute has_element?(view, "#images-#{oldest.id}")
      view |> element("#gallery-load-more") |> render_click()
      assert has_element?(view, "#images-#{oldest.id}")
      refute has_element?(view, "#gallery-load-more")
    end

    test "the start page shows the newest photos", %{conn: conn} do
      [_ | _] = images_fixture(admin_fixture(), 5)
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#home-gallery")
      assert Enum.count(Gallery.list_images(limit: 4)) == 4
    end
  end

  defp images_desc, do: Gallery.list_images(limit: 7)

  describe "dashboard gallery" do
    test "admins upload, caption and delete photos", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())
      {:ok, view, _html} = live(conn, ~p"/dashboard/gallery")

      photos =
        file_input(view, "#gallery-upload", :photos, [
          %{name: "a.png", content: File.read!(@png), type: "image/png"},
          %{name: "b.png", content: File.read!(@png), type: "image/png"}
        ])

      render_upload(photos, "a.png")
      render_upload(photos, "b.png")
      view |> form("#gallery-upload") |> render_submit()

      assert [image, _] = Gallery.list_images()
      assert "/uploads/" <> _ = image.image_url

      file =
        Path.join(
          Application.fetch_env!(:taamol, :uploads_dir),
          String.trim_leading(image.image_url, "/uploads/")
        )

      assert File.exists?(file)

      view
      |> form("#caption-#{image.id}", %{"image_id" => image.id, "caption" => "Ashura majlis"})
      |> render_submit()

      assert Gallery.get_image(image.id).caption == "Ashura majlis"

      view |> element("#delete-#{image.id}") |> render_click()
      refute Gallery.get_image(image.id)
      refute File.exists?(file)
    end

    test "regular users can't manage the gallery", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard/gallery")

      assert {:error, :forbidden} =
               Gallery.create_image(Scope.for_user(user_fixture()), "/uploads/x.png")
    end
  end
end
