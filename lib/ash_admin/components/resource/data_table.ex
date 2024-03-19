defmodule AshAdmin.Components.Resource.DataTable do
  @moduledoc false
  use Phoenix.LiveComponent

  import AshAdmin.Helpers
  import AshPhoenix.LiveView
  import Tails
  alias AshAdmin.Components.Resource.Table

  attr :resource, :atom
  attr :api, :atom
  attr :action, :any
  attr :authorizing, :boolean
  attr :actor, :any
  attr :url_path, :any
  attr :params, :any
  attr :table, :any, required: true
  attr :tables, :any, required: true
  attr :prefix, :any, required: true
  attr :tenant, :any, required: true
  attr :polymorphic_actions, :any, required: true

  def render(assigns) do
    ~H"""
    <div>
      <div class="sm:mt-0 bg-gray-300 min-h-screen">
        <div
          :if={@action.arguments != []}
          class="md:grid md:grid-cols-3 md:gap-6 md:mx-16 md:pt-10 mb-10"
        >
          <div class="md:mt-0 md:col-span-2">
            <div class="shadow-lg overflow-hidden pt-2 sm:rounded-md bg-white">
              <div class="px-4 sm:p-6">
                <.form
                  :let={form}
                  :if={@query}
                  as={:query}
                  for={@query}
                  phx-change="validate"
                  phx-submit="save"
                  phx-target={@myself}
                >
                  <%= AshAdmin.Components.Resource.Form.render_attributes(
                    assigns,
                    @resource,
                    @action,
                    form
                  ) %>
                  <div class="px-4 py-3 text-right sm:px-6">
                    <button
                      type="submit"
                      class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Run Query
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>

        <div :if={@tables != []} class="md:grid md:grid-cols-3 md:gap-6 md:mx-16 md:pt-10 mb-10">
          <div class="md:mt-0 md:col-span-2">
            <div class="px-4 sm:p-6">
              <AshAdmin.Components.Resource.SelectTable.table
                resource={@resource}
                action={@action}
                on_change="change_table"
                target={@myself}
                table={@table}
                tables={@tables}
                polymorphic_actions={@polymorphic_actions}
              />
            </div>
          </div>
        </div>

        <div :if={@action.arguments == [] || @params["args"]} class="h-full overflow-auto md:mx-4">
          <div class="shadow-lg overflow-auto sm:rounded-md bg-white">
            <div :if={match?({:error, _}, @data)}>
              <ul>
                <%= for {path, error} <- AshPhoenix.Form.errors(@query, for_path: :all) do %>
                  <%= for {field, message} <- error do %>
                    <li><%= Enum.join(path ++ [field], ".") %>: <%= message %></li>
                  <% end %>
                <% end %>
              </ul>
            </div>
            <div class="px-2">
              <%= render_pagination_links(assigns, :top) %>

              <div :if={@thousand_records_warning && !@action.get?}>
                Only showing up to 1000 rows. To show more, enable
                <a href="http://ash-hq.org/docs/guides/ash/2.5.9/topics/pagination">pagination</a>
                for the action in question.
              </div>
              <Table.table
                :if={match?({:ok, _data}, @data)}
                table={@table}
                data={data(@data)}
                resource={@resource}
                api={@api}
                attributes={AshAdmin.Resource.table_columns(@resource)}
                format_fields={AshAdmin.Resource.format_fields(@resource)}
                show_sensitive_fields={AshAdmin.Resource.show_sensitive_fields(@resource)}
                prefix={@prefix}
                actor={@actor}
              />
              <%= render_pagination_links(assigns, :bottom) %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:initialized, fn -> false end)
     |> assign_new(:default, fn -> nil end)
     |> assign_new(:page_params, fn -> nil end)
     |> assign_new(:page_num, fn -> nil end)
     |> assign_new(:thousand_records_warning, fn -> false end)}
  end

  def update(assigns, socket) do
    if assigns[:initialized] do
      {:ok, socket}
    else
      socket = assign(socket, assigns)
      params = socket.assigns[:params] || %{}
      arguments = params["args"]

      query =
        socket.assigns[:resource]
        |> AshPhoenix.Form.for_read(socket.assigns.action.name,
          as: "query",
          actor: socket.assigns[:actor],
          tenant: socket.assigns[:tenant],
          authorize?: socket.assigns[:authorizing]
        )

      query =
        if arguments do
          AshPhoenix.Form.validate(query, arguments)
        else
          query
        end

      socket = assign(socket, :query, query)

      socket =
        if params["page"] do
          default_limit =
            (socket.assigns[:action] && socket.assigns.action.pagination &&
               socket.assigns.action.pagination.default_limit) ||
              socket.assigns.action.pagination.max_page_size || 25

          count? =
            socket.assigns[:action] && socket.assigns.action.pagination &&
              socket.assigns.action.pagination.countable

          page_params =
            AshPhoenix.LiveView.page_from_params(params["page"], default_limit, !!count?)

          socket
          |> assign(
            :page_params,
            page_params
          )
          |> assign(
            :page_num,
            page_num_from_page_params(page_params)
          )
        else
          socket
          |> assign(:page_params, nil)
          |> assign(:page_num, 1)
        end

      socket =
        if assigns[:action].pagination do
          socket
          |> assign(:thousand_records_warning, false)
          |> keep_live(
            :data,
            fn socket ->
              default_limit =
                socket.assigns.action.pagination.default_limit ||
                  socket.assigns.action.pagination.max_page_size || 50

              count? = socket.assigns.action.pagination.countable

              page_params =
                if socket.assigns[:params]["page"] do
                  page_from_params(socket.assigns[:params]["page"], default_limit, !!count?)
                else
                  if socket.assigns.action.pagination.countable do
                    [limit: 50, count: true]
                  else
                    [limit: 50]
                  end
                end

              if socket.assigns[:tables] != [] &&
                   !socket.assigns[:table] do
                {:ok, []}
              else
                socket.assigns.query.source
                |> set_table(socket.assigns[:table])
                |> load_fields()
                |> assigns[:api].read(page: page_params)
              end
            end,
            load_until_connected?: true
          )
        else
          socket
          |> assign(:thousand_records_warning, true)
          |> keep_live(
            :data,
            fn socket ->
              if socket.assigns[:tables] != [] && !socket.assigns[:table] do
                {:ok, []}
              else
                socket.assigns.query.source
                |> set_table(socket.assigns[:table])
                |> Ash.Query.limit(1000)
                |> load_fields()
                |> assigns[:api].read()
              end
            end,
            load_until_connected?: true
          )
        end

      {:ok,
       socket
       |> assign(:initialized, true)}
    end
  end

  defp load_fields(query) do
    query
    |> Ash.Query.select([])
    |> Ash.Query.load(AshAdmin.Resource.table_columns(query.resource))
  end

  def handle_event("next_page", _, socket) do
    params = %{"page" => page_link_params(socket.assigns.data, "next")}

    {:noreply,
     push_patch(socket, to: self_path(socket.assigns.url_path, socket.assigns.params, params))}
  end

  def handle_event("prev_page", _, socket) do
    params = %{"page" => page_link_params(socket.assigns.data, "prev")}

    {:noreply,
     push_patch(socket, to: self_path(socket.assigns.url_path, socket.assigns.params, params))}
  end

  def handle_event("specific_page", %{"page" => page}, socket) do
    params = %{"page" => page_link_params(socket.assigns.data, String.to_integer(page))}

    {:noreply,
     push_patch(socket, to: self_path(socket.assigns.url_path, socket.assigns.params, params))}
  end

  def handle_event("validate", %{"query" => query}, socket) do
    query = AshPhoenix.Form.validate(socket.assigns.query, query)

    {:noreply, assign(socket, query: query)}
  end

  def handle_event("save", %{"query" => query_params}, socket) do
    {:noreply,
     push_redirect(
       socket,
       to: self_path(socket.assigns.url_path, socket.assigns.params, %{"args" => query_params})
     )}
  end

  def handle_event("change_table", %{"table" => %{"table" => table}}, socket) do
    {:noreply,
     push_redirect(socket,
       to: self_path(socket.assigns.url_path, socket.assigns.params, %{"table" => table})
     )}
  end

  def handle_event("add_form", %{"path" => path} = params, socket) do
    type =
      case params["type"] do
        "lookup" -> :read
        _ -> :create
      end

    form = AshPhoenix.Form.add_form(socket.assigns.form, path, type: type)

    {:noreply,
     socket
     |> assign(:form, form)}
  end

  def handle_event("remove_form", %{"path" => path}, socket) do
    form = AshPhoenix.Form.remove_form(socket.assigns.form, path)

    {:noreply,
     socket
     |> assign(:form, form)}
  end

  def handle_event("append_value", %{"path" => path, "field" => field}, socket) do
    list =
      AshPhoenix.Form.get_form(socket.assigns.form, path)
      |> AshPhoenix.Form.value(String.to_existing_atom(field))
      |> Kernel.||([])
      |> indexed_list()
      |> append_to_and_map(nil)

    params =
      put_in_creating(
        socket.assigns.form.params || %{},
        Enum.map(AshPhoenix.Form.parse_path!(socket.assigns.form, path) ++ [field], &to_string/1),
        list
      )

    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply,
     socket
     |> assign(:form, form)}
  end

  defp indexed_list(map) when is_map(map) do
    map
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
    |> Enum.sort()
    |> Enum.map(&map[to_string(&1)])
  rescue
    _ ->
      List.wrap(map)
  end

  defp indexed_list(other), do: List.wrap(other)

  defp append_to_and_map(list, value) do
    list
    |> Enum.concat([value])
    |> Enum.with_index()
    |> Map.new(fn {v, i} ->
      {"#{i}", v}
    end)
  end

  defp put_in_creating(map, [key], value) do
    Map.put(map || %{}, key, value)
  end

  defp put_in_creating(list, [key | rest], value) when is_list(list) do
    List.update_at(list, String.to_integer(key), &put_in_creating(&1, rest, value))
  end

  defp put_in_creating(map, [key | rest], value) do
    map
    |> Kernel.||(%{})
    |> Map.put_new(key, %{})
    |> Map.update!(key, &put_in_creating(&1, rest, value))
  end

  defp render_pagination_links(assigns, placement) do
    assigns = assign(assigns, :placement, placement)

    ~H"""
    <div
      :if={(offset?(@data) || keyset?(@data)) && show_pagination_links?(@data, @placement)}
      class="w-5/6 mx-auto"
    >
      <div class="bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6">
        <div class="flex-1 flex justify-between sm:hidden">
          <button
            :if={!(keyset?(@data) && is_nil(@params["page"])) && prev_page?(@data)}
            phx-target={@myself}
            phx-click="prev_page"
            class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:text-gray-500"
          >
            Previous
          </button>
          <%= render_pagination_information(assigns, true) %>
          <button
            :if={next_page?(@data)}
            phx-click="next_page"
            phx-target={@myself}
            class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:text-gray-500"
          >
            Next
          </button>
        </div>
        <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
          <div>
            <%= render_pagination_information(assigns) %>
          </div>
          <div>
            <nav
              class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px"
              aria-label="Pagination"
            >
              <button
                :if={!(keyset?(@data) && is_nil(@params["page"])) && prev_page?(@data)}
                phx-click="prev_page"
                phx-target={@myself}
                class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
              >
                <span class="sr-only">Previous</span>

                <svg
                  class="h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path
                    fill-rule="evenodd"
                    d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
              <span :if={offset?(@data)}>
                <%= render_page_links(assigns, leading_page_nums(@data)) %>
                <%= render_middle_page_num(assigns, @page_num, trailing_page_nums(@data)) %>
                <%= render_page_links(assigns, trailing_page_nums(@data)) %>
              </span>
              <button
                :if={next_page?(@data)}
                phx-click="next_page"
                phx-target={@myself}
                class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
              >
                <span class="sr-only">Next</span>

                <svg
                  class="h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path
                    fill-rule="evenodd"
                    d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              </button>
            </nav>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_page_links(assigns, page_nums) do
    assigns = assign(assigns, page_nums: page_nums)

    ~H"""
    <button
      :for={i <- @page_nums}
      phx-click="specific_page"
      phx-target={@myself}
      phx-value-page={i}
      class={
        classes([
          "relative inline-flex items-center px-4 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50",
          "bg-gray-300": @page_num == i
        ])
      }
    >
      <%= i %>
    </button>
    """
  end

  defp render_pagination_information(assigns, small? \\ false) do
    assigns = assign(assigns, :small, small?)

    ~H"""
    <p class={classes(["text-sm text-gray-700", "sm:hidden": @small])}>
      <span :if={offset?(@data)}>
        Showing <span class="font-medium"><%= first(@data) %></span>
        to <span class="font-medium"><%= last(@data) %></span>
        <%= if count(@data) do %>
          of
        <% end %>
      </span>
      <span :if={count(@data)}>
        <span class="font-medium"><%= count(@data) %></span> results
      </span>
    </p>
    """
  end

  defp page_num_from_page_params(params) do
    cond do
      !params[:offset] || params[:after] || params[:before] ->
        1

      params[:offset] && params[:limit] ->
        trunc(Float.ceil(params[:offset] / params[:limit])) + 1

      true ->
        nil
    end
  end

  defp show_pagination_links?({:ok, _page}, :bottom), do: true
  defp show_pagination_links?({:ok, page}, :top), do: page.limit >= 20
  defp show_pagination_links?(_, _), do: false

  defp first({:ok, %Ash.Page.Offset{offset: offset}}) do
    (offset || 0) + 1
  end

  defp first(_), do: nil

  defp last({:ok, %Ash.Page.Offset{offset: offset, results: results}}) do
    Enum.count(results) + offset
  end

  defp last(_), do: nil

  defp render_middle_page_num(assigns, num, trailing_page_nums) do
    ellipsis? = num in trailing_page_nums || num <= 3

    assigns =
      assign(assigns, num: num, trailing_page_nums: trailing_page_nums, ellipsis: ellipsis?)

    ~H"""
    <span
      :if={show_ellipses?(@data)}
      class={
        classes([
          "relative inline-flex items-center px-4 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700",
          "bg-gray-300": !@ellipsis
        ])
      }
    >
      <span :if={@ellipsis}>
        ...
      </span>
      <span :if={!@ellipsis}>
        <%= @num %>
      </span>
    </span>
    """
  end

  defp show_ellipses?(%Ash.Page.Offset{count: count, limit: limit}) when not is_nil(count) do
    page_nums =
      count
      |> Kernel./(limit)
      |> Float.ceil()
      |> trunc()

    page_nums > 6
  end

  defp show_ellipses?({:ok, data}), do: show_ellipses?(data)
  defp show_ellipses?(_), do: false

  def leading_page_nums({:ok, data}), do: leading_page_nums(data)
  def leading_page_nums(%Ash.Page.Offset{count: nil}), do: []

  def leading_page_nums(%Ash.Page.Offset{limit: limit, count: count}) do
    page_nums =
      count
      |> Kernel./(limit)
      |> Float.ceil()
      |> trunc()

    1..min(3, page_nums)
  end

  def leading_page_nums(_), do: []

  def trailing_page_nums({:ok, data}), do: trailing_page_nums(data)
  def trailing_page_nums(%Ash.Page.Offset{count: nil}), do: []

  def trailing_page_nums(%Ash.Page.Offset{limit: limit, count: count}) do
    page_nums =
      count
      |> Kernel./(limit)
      |> Float.ceil()
      |> trunc()

    if page_nums > 3 do
      max(page_nums - 2, 4)..page_nums
    else
      []
    end
  end

  defp data({:ok, data}), do: data(data)
  defp data({:error, _}), do: []
  defp data(%Ash.Page.Offset{results: results}), do: results
  defp data(%Ash.Page.Keyset{results: results}), do: results
  defp data(data), do: data

  defp offset?({:ok, data}), do: offset?(data)
  defp offset?(%Ash.Page.Offset{}), do: true
  defp offset?(_), do: false

  defp keyset?({:ok, data}), do: keyset?(data)
  defp keyset?(%Ash.Page.Keyset{}), do: true
  defp keyset?(_), do: false

  defp count({:ok, %{count: count}}), do: count
  defp count(%{count: count}), do: count
  defp count(_), do: nil
end
