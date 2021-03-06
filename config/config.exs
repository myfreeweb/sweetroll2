use Mix.Config

config :mnesia, dir: 'priv/db/#{Mix.env()}/#{node()}'

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :microformats2, atomize_keys: false, underscore_keys: false

config :logger, :console,
  format:
    if(Mix.env() == :prod, do: {Timber.Formatter, :format}, else: {NiceLogFormatter, :format}),
  colors: [enabled: false],
  metadata: :all,
  handle_sasl_reports: true

config :floki, :html_parser, Floki.HTMLParser.Html5ever

config :liquid,
  extra_tags: %{
    head: {Sweetroll2.Render.LiquidTags.Head, Liquid.Tag},
    header: {Sweetroll2.Render.LiquidTags.Header, Liquid.Tag},
    footer: {Sweetroll2.Render.LiquidTags.Footer, Liquid.Tag},
    feedpreview: {Sweetroll2.Render.LiquidTags.FeedPreview, Liquid.Tag}
  }

config :event_bus, topics: [:url_updated, :upload_processed], id_generator: EventBus.Util.Base62

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :ex_aws,
  json_codec: Jason,
  region: {:system, "SR2_S3_REGION"}

config :sweetroll2, Sweetroll2.Application.Scheduler,
  jobs:
    [
      {"@reboot", {Sweetroll2.Job.Compress, :enqueue_assets, []}},
      {"0 */2 * * *", {Sweetroll2.Job.ClearJobs, :enqueue, []}}
    ] ++
      if(Mix.env() == :prod,
        do: [
          {"1 */2 * * *", {Sweetroll2.Job.Backup, :enqueue, []}},
          {"30 0 */2 * *", {Sweetroll2.Job.SendWebmentions, :enqueue_all, []}},
          {"0 */6 * * *", {Sweetroll2.Job.Generate, :enqueue_all, []}}
        ],
        else: []
      )
