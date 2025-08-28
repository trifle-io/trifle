// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

// Simple configuration without Node.js dependencies for production builds

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex",
    "../lib/trifle_app/**/*.*ex",
    "../lib/trifle_api/**/*.*ex",
    "../lib/trifle_admin/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      }
    },
  },
  plugins: [
    // Removed Node.js dependencies for production builds
    // Hero icons and LiveView variants can be added with runtime: Mix.env() == :dev conditionals
  ]
}
