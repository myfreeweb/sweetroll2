defmodule Sweetroll2.Events do
  @moduledoc """
  A GenServer for automatic event handling.
  """

  @debounce_ms 2000

  require Logger
  alias Sweetroll2.{Post, Job}
  use EventBus.EventSource
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    EventBus.subscribe({__MODULE__, ["url_updated"]})
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:url_updated, _id} = event_shadow, state) do
    %{data: %SSE.Chunk{data: url}} = EventBus.fetch_event(event_shadow)

    Job.Generate.remove_generated(url)
    Sweetroll2.Post.DynamicUrls.Cache.clear()

    Que.add(Job.Generate,
      urls: [url],
      next_jobs: [
        {Job.NotifyWebsub, url: Sweetroll2.canonical_home_url() <> url},
        {Job.SendWebmentions, url: url, our_home_url: Sweetroll2.canonical_home_url()}
      ]
    )

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:notify_url_for_real, url}, state) do
    Logger.debug("finished debounce for url '#{url}', notifying event bus",
      event: %{debounce_finished: %{url: url}}
    )

    EventSource.notify(%{topic: :url_updated}, do: %SSE.Chunk{data: url})
    {:noreply, Map.delete(state, url)}
  end

  @impl true
  def handle_cast({:notify_url_req, url}, state) do
    if Map.has_key?(state, url) do
      Debounce.apply(state[url])

      Logger.debug("reset debounce for url '#{url}': #{inspect(state[url])}",
        event: %{debounce_reset: %{url: url}}
      )

      {:noreply, state}
    else
      {:ok, pid} =
        Debounce.start_link(
          {GenServer, :cast, [__MODULE__, {:notify_url_for_real, url}]},
          @debounce_ms
        )

      Debounce.apply(pid)

      Logger.debug("started debounce for url '#{url}': #{inspect(pid)}",
        event: %{debounce_started: %{url: url}}
      )

      {:noreply, Map.put(state, url, pid)}
    end
  end

  @doc "callback for EventBus"
  def process(event_shadow) do
    GenServer.cast(__MODULE__, event_shadow)
    :ok
  end

  def notify_urls_updated([]) do
  end

  def notify_urls_updated(urls) when is_list(urls) do
    for url <- urls do
      GenServer.cast(__MODULE__, {:notify_url_req, url})
      aff = affected_urls(url)

      Logger.info("updating affected urls",
        event: %{affected_discovered: %{url: url, affected: aff}}
      )

      notify_urls_updated(aff)
    end
  end

  defp affected_urls(url) do
    posts = %Post.DbAsMap{}

    if is_nil(posts[url]) do
      []
    else
      local_urls = Post.urls_local()

      Post.Feed.filter_feeds(local_urls, posts)
      |> Stream.filter(&Post.Feed.in_feed?(posts[url], posts[&1]))
      |> Enum.flat_map(
        &[&1 | Map.keys(Post.DynamicUrls.dynamic_urls_for(posts[&1], posts, local_urls))]
      )
    end
  end
end
