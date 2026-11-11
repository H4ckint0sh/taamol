defmodule TaamolWeb.DashboardLive do
  use TaamolWeb, :live_view

  alias Taamol.Accounts

  @impl true
  def mount(_params, _session, socket) do
    case Accounts.dashboard_stats(socket.assigns.current_scope) do
      {:ok, stats} -> {:ok, assign(socket, stats: stats, page_title: "Dashboard")}
      {:error, :forbidden} -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div id="admin-dashboard" class="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-16 lg:px-8">
        <div class="flex flex-wrap items-end justify-between gap-6">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
              Administration
            </p>
            <h1 class="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">Dashboard</h1>
            <p class="mt-3 text-base-content/65">A quick overview of your Taamol community.</p>
          </div>
          <.link
            id="dashboard-manage-access"
            href={~p"/admin/access"}
            class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-3 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            Manage access <.icon name="hero-arrow-up-right" class="size-4" />
          </.link>
        </div>

        <section aria-label="Account overview" class="mt-10 grid gap-4 sm:grid-cols-3">
          <div id="dashboard-users" class="rounded-2xl border border-base-300 bg-base-100 p-6">
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium text-base-content/65">Total accounts</p>
              <.icon name="hero-users" class="size-5 text-primary" />
            </div>
            <p class="mt-5 text-4xl font-semibold tracking-tight">{@stats.users}</p>
            <p class="mt-2 text-sm text-base-content/55">Registered users</p>
          </div>
          <div id="dashboard-confirmed" class="rounded-2xl border border-base-300 bg-base-100 p-6">
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium text-base-content/65">Confirmed accounts</p>
              <.icon name="hero-check-badge" class="size-5 text-primary" />
            </div>
            <p class="mt-5 text-4xl font-semibold tracking-tight">{@stats.confirmed}</p>
            <p class="mt-2 text-sm text-base-content/55">Email addresses verified</p>
          </div>
          <div id="dashboard-admins" class="rounded-2xl border border-base-300 bg-base-100 p-6">
            <div class="flex items-center justify-between">
              <p class="text-sm font-medium text-base-content/65">Administrators</p>
              <.icon name="hero-shield-check" class="size-5 text-primary" />
            </div>
            <p class="mt-5 text-4xl font-semibold tracking-tight">{@stats.admins}</p>
            <p class="mt-2 text-sm text-base-content/55">Accounts with admin access</p>
          </div>
        </section>

        <div class="mt-8 rounded-2xl bg-base-200 p-6 sm:p-8">
          <div class="flex flex-wrap items-center justify-between gap-5">
            <div>
              <h2 class="text-lg font-semibold">People and permissions</h2>
              <p class="mt-1 text-sm text-base-content/65">
                Review administrator roles and control dashboard access.
              </p>
            </div>
            <.link
              href={~p"/admin/access"}
              class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
            >
              Open access management <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
