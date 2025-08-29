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
  darkMode: 'class', // Enable class-based dark mode
  safelist: [
    // Force include essential dark mode classes
    'dark:bg-slate-900',
    'dark:bg-slate-800', 
    'dark:bg-slate-700',
    'dark:text-white',
    'dark:text-slate-400',
    'dark:text-slate-300',
    'dark:border-slate-600',
    'dark:border-slate-700',
    'dark:divide-slate-700',
    'dark:hover:bg-slate-700',
    'dark:hover:text-white'
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
