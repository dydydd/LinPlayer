import { defineConfig } from 'vitepress'

const SITE_URL = 'https://linplayer.902541.xyz'
const REPO_URL = 'https://github.com/zzzwannasleep/LinPlayer'

export default defineConfig({
  lang: 'zh-CN',
  title: 'LinPlayer Wiki',
  description: 'LinPlayer 使用文档与开发者文档。',

  lastUpdated: true,
  cleanUrls: true,

  sitemap: {
    hostname: SITE_URL,
  },

  head: [
    ['meta', { name: 'theme-color', content: '#02569B' }],
    ['link', { rel: 'icon', type: 'image/jpeg', href: '/app_icon.jpg' }],
    ['link', { rel: 'apple-touch-icon', href: '/app_icon.jpg' }],
  ],

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: '指南', link: '/guide/quickstart' },
      { text: '下载', link: '/download' },
      { text: '文档', link: '/SERVER_IMPORT' },
      { text: '开发', link: '/dev/' },
      { text: '部署', link: '/deploy/cloudflare-pages' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: '指南',
          items: [
            { text: '快速开始', link: '/guide/quickstart' },
            { text: '播放页操作', link: '/guide/playback' },
            { text: '界面一览', link: '/guide/ui' },
            { text: '常见问题', link: '/guide/faq' },
          ],
        },
      ],
      '/deploy/': [
        {
          text: '部署',
          items: [{ text: 'Cloudflare Pages', link: '/deploy/cloudflare-pages' }],
        },
      ],
      '/dev/': [
        {
          text: '开发',
          items: [
            { text: '开发者文档', link: '/dev/' },
            { text: '插件宿主清单（V1）', link: '/dev/PLUGIN_HOST_V1' },
            { text: '插件作者规范（V1）', link: '/dev/PLUGIN_SPEC_V1' },
            { text: '源码导览 / 架构', link: '/dev/ARCHITECTURE' },
            { text: '播放内核优化', link: '/dev/PLAYER_CORE_OPTIMIZATION' },
            { text: '桌面端 UI 架构', link: '/dev/DESKTOP_UI_ARCHITECTURE' },
            { text: 'Android 签名（OTA）', link: '/dev/ANDROID_SIGNING' },
            { text: 'TV 代理路线图', link: '/dev/TV_PROXY_ROADMAP' },
          ],
        },
      ],
      '/': [
        {
          text: '文档',
          items: [
            { text: '下载', link: '/download' },
            { text: '从分享文本导入服务器', link: '/SERVER_IMPORT' },
            { text: '开发者文档', link: '/dev/' },
          ],
        },
      ],
    },

    search: {
      provider: 'local',
    },

    socialLinks: [{ icon: 'github', link: REPO_URL }],

    editLink: {
      pattern: `${REPO_URL}/edit/main/docs/:path`,
      text: '在 GitHub 上编辑此页',
    },

    footer: {
      message: 'Built with VitePress',
    },
  },
})
