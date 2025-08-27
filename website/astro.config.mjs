import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

// https://astro.build/config
export default defineConfig({
  output: 'static',
  site: "https://instantdb-flutter-docs.pages.dev",
  integrations: [
    starlight({
      title: "InstantDB Flutter",
      social: {
        github: "https://github.com/pillowsoft/instantdb_flutter",
      },
      customCss: ["/src/styles/custom.css", "/src/fonts/font-face.css"],
      sidebar: [
        { label: "Getting Started", autogenerate: { directory: "getting-started" } },
        { label: "Core Concepts", autogenerate: { directory: "concepts" } },
        { label: "Queries", autogenerate: { directory: "queries" } },
        { label: "Real-time", autogenerate: { directory: "realtime" } },
        { label: "Flutter Widgets", autogenerate: { directory: "flutter" } },
        { label: "Authentication", autogenerate: { directory: "auth" } },
        { label: "Advanced", autogenerate: { directory: "advanced" } },
        { label: "API Reference", autogenerate: { directory: "api" } },
      ],
    }),
  ],
});
