'use client';

import React, { useEffect, useRef, useState } from 'react';
import { TriangleAlert } from 'lucide-react';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SitePage';
import { AppScreenshot } from '@/components/AppScreenshot';
import './support.css';

const supportSections = [
  {
    "id": "faq",
    "label": "Getting started",
    "depth": 0
  },
  {
    "id": "faq-what-is-herdcats",
    "label": "About Herdcats",
    "depth": 1
  },
  {
    "id": "faq-what-is-herdr-and-how-is-it-different-from-herdcats",
    "label": "Herdr and Herdcats",
    "depth": 1
  },
  {
    "id": "faq-what-do-i-need-before-i-connect",
    "label": "Requirements",
    "depth": 1
  },
  {
    "id": "faq-can-i-use-herdcats-if-my-computer-doesn-t-have-herdr-installed",
    "label": "Herdr required",
    "depth": 1
  },
  {
    "id": "faq-do-i-need-tailscale",
    "label": "Tailscale",
    "depth": 1
  },
  {
    "id": "faq-do-i-need-any-other-software-on-my-computer",
    "label": "Required software",
    "depth": 1
  },
  {
    "id": "privacy",
    "label": "Signing in and privacy",
    "depth": 0
  },
  {
    "id": "privacy-can-i-sign-in-with-a-password-or-ssh-key",
    "label": "Passwords and SSH keys",
    "depth": 1
  },
  {
    "id": "privacy-do-i-have-to-enter-my-key-s-passphrase-every-time",
    "label": "Remembering passphrases",
    "depth": 1
  },
  {
    "id": "privacy-what-is-the-fingerprint-the-app-asks-me-to-approve",
    "label": "Server fingerprints",
    "depth": 1
  },
  {
    "id": "privacy-why-is-a-changed-host-key-blocking-my-connection",
    "label": "Changed host keys",
    "depth": 1
  },
  {
    "id": "privacy-where-are-my-saved-sign-in-details-stored",
    "label": "Saved credentials",
    "depth": 1
  },
  {
    "id": "privacy-is-voice-dictation-always-processed-on-my-iphone",
    "label": "Dictation privacy",
    "depth": 1
  },
  {
    "id": "using-app",
    "label": "Using the app",
    "depth": 0
  },
  {
    "id": "using-app-what-are-spaces-agents-tabs-and-panes",
    "label": "Spaces and panes",
    "depth": 1
  },
  { "id": "using-app-tui-or-core", "label": "TUI or Herdr Core", "depth": 1 },
  { "id": "using-app-ipad-duo", "label": "iPad and iPhone Duo", "depth": 1 },
  {
    "id": "using-app-when-should-i-use-live-compose-or-voice",
    "label": "Views and Compose",
    "depth": 1
  },
  {
    "id": "using-app-what-is-the-timeline-helper-and-why-does-timeline-need-it",
    "label": "Herdcats Bridge",
    "depth": 1
  },
  { "id": "using-app-pi", "label": "Pi setup", "depth": 1 },
  { "id": "using-app-cursor", "label": "Cursor Agent", "depth": 1 },
  { "id": "using-app-phone-answers", "label": "Phone answers", "depth": 1 },
  { "id": "using-app-model-controls", "label": "Models and effort", "depth": 1 },
  {
    "id": "using-app-codex-shared-background-server",
    "label": "Codex background server",
    "depth": 1
  },
  {
    "id": "using-app-does-herdcats-run-agents-on-my-iphone",
    "label": "Where agents run",
    "depth": 1
  },
  {
    "id": "using-app-can-i-send-photos",
    "label": "Photos",
    "depth": 1
  },
  {
    "id": "using-app-what-happens-when-i-switch-apps-or-lock-my-phone",
    "label": "Background refresh",
    "depth": 1
  },
  {
    "id": "using-app-can-i-choose-a-different-herdr-session",
    "label": "Herdr sessions",
    "depth": 1
  },
  {
    "id": "using-app-can-i-switch-between-computers-without-signing-in-to-each-one-on-my-phone",
    "label": "Switching machines",
    "depth": 1
  },
  {
    "id": "using-app-how-do-i-add-another-machine",
    "label": "Adding machines",
    "depth": 1
  },
  {
    "id": "connect",
    "label": "How to connect",
    "depth": 0
  },
  {
    "id": "macos-setup",
    "label": "SSH on macOS",
    "depth": 0
  },
  {
    "id": "macos-setup-enable-remote-login",
    "label": "Remote Login",
    "depth": 1
  },
  {
    "id": "macos-setup-generate-an-ed25519-key-authorize-it",
    "label": "Create an SSH key",
    "depth": 1
  },
  {
    "id": "macos-setup-transfer-the-private-key-to-herdcats",
    "label": "Import your key",
    "depth": 1
  },
  {
    "id": "macos-setup-find-host-username",
    "label": "Host and username",
    "depth": 1
  },
  {
    "id": "linux-setup",
    "label": "SSH on Linux",
    "depth": 0
  },
  {
    "id": "linux-setup-ensure-openssh-server-is-installed-running",
    "label": "Install OpenSSH",
    "depth": 1
  },
  {
    "id": "linux-setup-generate-authorize-key",
    "label": "Authorize your key",
    "depth": 1
  },
  {
    "id": "linux-setup-check-firewall-herdr-binary-location",
    "label": "Firewall and Herdr",
    "depth": 1
  },
  {
    "id": "windows-setup",
    "label": "SSH on Windows / WSL",
    "depth": 0
  },
  {
    "id": "windows-setup-option-a-wsl-2-recommended",
    "label": "WSL 2",
    "depth": 1
  },
  {
    "id": "windows-setup-option-b-native-windows-openssh-server",
    "label": "Windows OpenSSH",
    "depth": 1
  },
  {
    "id": "ssh-keys",
    "label": "SSH keys",
    "depth": 0
  },
  {
    "id": "ssh-keys-why-ed25519",
    "label": "Ed25519 keys",
    "depth": 1
  },
  {
    "id": "ssh-keys-passphrase-notice",
    "label": "Passphrases",
    "depth": 1
  },
  {
    "id": "ssh-keys-on-device-keychain",
    "label": "Keychain storage",
    "depth": 1
  },
  {
    "id": "ssh-keys-shoulder-surfing-protection",
    "label": "Key masking",
    "depth": 1
  },
  {
    "id": "troubleshooting",
    "label": "Troubleshooting",
    "depth": 0
  },
  {
    "id": "troubleshooting-authentication-failed-check-username-and-password-key",
    "label": "Authentication failed",
    "depth": 1
  },
  {
    "id": "troubleshooting-host-key-verification-failed-changed",
    "label": "Host key errors",
    "depth": 1
  },
  {
    "id": "troubleshooting-connection-timeout-host-unreachable",
    "label": "Connection timeout",
    "depth": 1
  },
  {
    "id": "troubleshooting-herdr-command-not-found",
    "label": "Herdr not found",
    "depth": 1
  },
  { "id": "troubleshooting-core-only-mac", "label": "Herdr Core–only Mac", "depth": 1 },
  { "id": "troubleshooting-offline-retry", "label": "Offline and Retry", "depth": 1 },
  {
    "id": "troubleshooting-timeline-helper-missing-or-install-failed",
    "label": "Herdcats Bridge",
    "depth": 1
  },
  {
    "id": "troubleshooting-codex-session-not-identified",
    "label": "Codex session not identified",
    "depth": 1
  }
];

export default function SupportPage() {
  const scrollRoot = useRef<HTMLDivElement>(null);
  const [activeSection, setActiveSection] = useState('faq');

  useEffect(() => {
    const root = scrollRoot.current;
    if (!root) return;
    let frame = 0;
    const updateSection = () => {
      frame = 0;
      const threshold = root.getBoundingClientRect().top + (window.innerWidth <= 800 ? 100 : 48);
      let current = supportSections[0].id;
      for (const section of supportSections) {
        const element = document.getElementById(section.id);
        if (element && element.getBoundingClientRect().top <= threshold) current = section.id;
      }
      if (root.scrollTop > 0 && root.scrollHeight - root.scrollTop - root.clientHeight <= 4) {
        current = supportSections[supportSections.length - 1].id;
      }
      setActiveSection(current);
    };
    const scheduleUpdate = () => {
      if (!frame) frame = requestAnimationFrame(updateSection);
    };
    const observer = new ResizeObserver(scheduleUpdate);
    const content = root.querySelector('.support-content');
    if (content) observer.observe(content);
    root.addEventListener('scroll', scheduleUpdate, { passive: true });
    window.addEventListener('resize', scheduleUpdate);
    updateSection();
    return () => {
      root.removeEventListener('scroll', scheduleUpdate);
      window.removeEventListener('resize', scheduleUpdate);
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, []);
  useEffect(() => {
    const keepActiveLinkVisible = () => {
      const sidebar = scrollRoot.current?.querySelector<HTMLElement>('.support-sidebar');
      const link = sidebar?.querySelector<HTMLElement>('[aria-current="location"]');
      if (!sidebar || !link) return;
      const mobile = window.matchMedia('(max-width: 800px)').matches;
      const container = mobile ? sidebar.querySelector<HTMLElement>('nav') : sidebar;
      if (!container) return;
      const viewport = container.getBoundingClientRect();
      const target = link.getBoundingClientRect();
      // Scroll only the navigation container, leaving the article in place.
      if (mobile) {
        const left = target.left < viewport.left ? target.left - viewport.left
          : target.right > viewport.right ? target.right - viewport.right : 0;
        if (left) container.scrollBy({ left, behavior: 'instant' });
      } else {
        const top = target.top < viewport.top ? target.top - viewport.top
          : target.bottom > viewport.bottom ? target.bottom - viewport.bottom : 0;
        if (top) container.scrollBy({ top, behavior: 'instant' });
      }
    };
    keepActiveLinkVisible();
    window.addEventListener('resize', keepActiveLinkVisible);
    return () => window.removeEventListener('resize', keepActiveLinkVisible);
  }, [activeSection]);

  const [copiedIndex, setCopiedIndex] = useState<string | null>(null);

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedIndex(id);
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  return (
    <div className="support-wrapper" ref={scrollRoot}>
      <SiteHeader current="support" title="Support">
        <p>Find answers, connect your iPhone or iPad to Herdr, and switch between your machines.</p>
        <p>Still stuck? Email <a href="mailto:hello@enchantinglabs.com">hello@enchantinglabs.com</a> or open an issue on <a href="https://github.com/zhiyao/herdcats/issues" target="_blank" rel="noopener noreferrer">GitHub</a>. Leave out passwords, keys and passphrases.</p>
      </SiteHeader>

      {/* Main Content */}
      <main className="support-main">
        <aside className="support-sidebar">
          <nav aria-label="Support sections">
            <p className="sidebar-title">Support guide</p>
            {supportSections.map((section) => (
              <a key={section.id} href={`#${section.id}`}
                className={`section-link${section.depth ? ' subsection-link' : ''}${activeSection === section.id ? ' active' : ''}`}
                aria-current={activeSection === section.id ? 'location' : undefined}>
                {section.label}
              </a>
            ))}
          </nav>
        </aside>
        <div className="support-content">
        {/* Hero Section */}
        <section className="hero-section">
          <div className="security-banner">
            <div className="security-text">
              <strong>Direct &amp; Secure:</strong> No intermediate relays, proxies, or cloud daemons.
              Credentials stay encrypted in your iPhone’s on-device Keychain.
              <span className="ts-tag">Tailscale Recommended</span>
            </div>
          </div>
        </section>

        <section id="faq" aria-labelledby="faq-title" className="guide-card faq-section">
        <h2 id="faq-title">Frequently asked questions</h2>
        <p className="card-desc">Help with connecting your iPhone and using Herdcats. Some features depend on your app version.</p>
        <h3 className="faq-category">Getting started</h3>
        <div className="faq-list">
        <div className="faq-item">
        <h4 id="faq-what-is-herdcats" className="faq-question">What is Herdcats?</h4>
        <p>Herdcats lets you use Herdr from your iPhone or iPad: browse your spaces and agents, read terminal output, and send messages, keystrokes, dictation, and photos. Save a separate SSH connection for each computer and switch between them in the machine selector. It requires iOS 17 or later. On iPad and the unfolded iPhone Duo, you can keep two panes open side by side.</p>
        </div>
        <div className="faq-item">
        <h4 id="faq-what-is-herdr-and-how-is-it-different-from-herdcats" className="faq-question">What is Herdr, and how is it different from Herdcats?</h4>
        <p>Herdr runs on your computer and organizes the spaces, agents, and terminal panes you work with. Herdcats is the iPhone and iPad app that connects to it. Your agents and their work stay on the computer.</p>
        <p>Herdcats can connect to either Herdr runtime: the Herdr TUI (the <code>herdr</code> command) or Herdr Core (the <code>hc</code> command, which the Herdr desktop app installs and runs). See <a href="#using-app-tui-or-core">TUI or Herdr Core</a>.</p>
        </div>
        <div className="faq-item">
        <h4 id="faq-what-do-i-need-before-i-connect" className="faq-question">What do I need before I connect?</h4>
        <p>You need:</p>
        <ul>
        <li>A computer running Herdr: the Herdr TUI with its default session started, or Herdr Core, for example through the Herdr desktop app.</li>
        <li>SSH access enabled on that computer. SSH lets the app connect securely.</li>
        <li>A network connection that lets your iPhone reach the computer.</li>
        <li>The computer&#x27;s hostname or IP address, SSH port, account username, and   password or a supported SSH private key.</li>
        </ul>
        <p>Use the computer account that runs Herdr when signing in from Herdcats. Add another computer as its own saved SSH connection in Herdcats; the app connects directly to the selected computer.</p>
        <p>Follow <a href="#connect">How to connect</a> to enable SSH on your computer.</p>
        </div>
        <div className="faq-item">
        <h4 id="faq-can-i-use-herdcats-if-my-computer-doesn-t-have-herdr-installed" className="faq-question">Can I use Herdcats if my computer doesn&#x27;t have Herdr installed?</h4>
        <p>No. Herdcats needs Herdr on the computer to show spaces, agents, and panes. SSH access alone is not enough. If SSH connects but Herdr is missing, the app shows <strong>“SSH worked. Herdr was not found.”</strong></p>
        <p>Install the Herdr TUI or Herdr Core on that computer using the account that you connect with, start it, then try again. If the computer already runs the Herdr desktop app, don&rsquo;t install the TUI as well; see <a href="#troubleshooting-core-only-mac">Herdr Core–only Mac</a>. Herdcats does not install Herdr for you or provide a standalone SSH terminal. If someone else manages the computer, ask them to set up Herdr and SSH access for your account.</p>
        </div>
        <div className="faq-item">
        <h4 id="faq-do-i-need-tailscale" className="faq-question">Do I need Tailscale?</h4>
        <p>Tailscale is recommended for connecting your phone and computer, including when you are away from home. Both devices should be on the same Tailscale network. Another network works too, as long as your phone can reach the computer&#x27;s SSH server.</p>
        </div>
        <div className="faq-item">
        <h4 id="faq-do-i-need-any-other-software-on-my-computer" className="faq-question">Do I need any other software on my computer?</h4>
        <p>Herdr and SSH are required. Terminal, Compose, voice, and photos need nothing else. Herdr Core connections never need anything else. The optional Timeline view, for TUI connections, does: Herdcats Bridge (<code>herdcats-bridge</code>) on the computer you connect to directly. A terminal pane is a scrolling log; Herdcats Bridge reads supported Claude, Codex, Agy, Pi, and Cursor Agent sessions&#x27; structured transcripts so Herdcats can show them as readable messages, tool activity, and images instead. It is installed only when you tap Install, runs only while Timeline is open, and everything else works without it. The optional <code>quota-axi</code> tool adds provider quota information.</p>
        </div>
        </div>
        <h3 id="privacy" className="faq-category">Signing in and privacy</h3>
        <div className="faq-list">
        <div className="faq-item">
        <h4 id="privacy-can-i-sign-in-with-a-password-or-ssh-key" className="faq-question">Can I sign in with a password or SSH key?</h4>
        <p>You can use your computer account&#x27;s password or an OpenSSH ed25519 private key. Other private-key formats are unsupported.</p>
        <p>Passphrase-protected ed25519 keys are supported with these settings: AES-128-CTR or AES-256-CTR encryption and bcrypt at 1–256 rounds. If your key is rejected, check your app version and ask your administrator to confirm the key format.</p>
        </div>
        <div className="faq-item">
        <h4 id="privacy-do-i-have-to-enter-my-key-s-passphrase-every-time" className="faq-question">Do I have to enter my key&#x27;s passphrase every time?</h4>
        <p>Remembering the passphrase is optional. If you choose not to save it, you will need to unlock the key again after restarting the app.</p>
        </div>
        <div className="faq-item">
        <h4 id="privacy-what-is-the-fingerprint-the-app-asks-me-to-approve" className="faq-question">What is the fingerprint the app asks me to approve?</h4>
        <p>It identifies the computer&#x27;s SSH server. Checking it helps ensure you are connecting to the intended computer. Compare it with a fingerprint obtained directly from that computer or its administrator before approving it. Herdcats remembers the approved host key for that hostname and port.</p>
        </div>
        <div className="faq-item">
        <h4 id="privacy-why-is-a-changed-host-key-blocking-my-connection" className="faq-question">Why is a changed host key blocking my connection?</h4>
        <p>The computer is presenting a different identity from the one you approved. This can happen after a server is rebuilt, but you should verify the reason with its administrator before restoring access. Herdcats blocks the connection, including automatic reconnects. When the changed-key review appears, compare the new fingerprint with one obtained directly from your computer or its administrator through a trusted channel. Confirm that you verified it, then choose “Replace Approved Key and Connect”. Canceling keeps the previously approved key.</p>
        </div>
        <div className="faq-item">
        <h4 id="privacy-where-are-my-saved-sign-in-details-stored" className="faq-question">Where are my saved sign-in details stored?</h4>
        <p>Remembered credentials and approved host keys are stored in your iPhone&#x27;s Keychain. Keep passwords, private keys, and passphrases out of screenshots and support reports.</p>
        </div>
        <div className="faq-item">
        <h4 id="privacy-is-voice-dictation-always-processed-on-my-iphone" className="faq-question">Is voice dictation always processed on my iPhone?</h4>
        <p>Herdcats uses Apple&#x27;s speech recognition and requests on-device processing when available. Availability depends on your device and language, so local processing is not guaranteed. Dictation requires microphone and speech recognition permissions. Review the text before sending it.</p>
        </div>
        </div>
        <h3 id="using-app" className="faq-category">Using the app</h3>
        <div className="faq-list">
        <div className="faq-item">
        <h4 id="using-app-what-are-spaces-agents-tabs-and-panes" className="faq-question">What are spaces, agents, tabs, and panes?</h4>
        <p>These are the items in your Herdr session. Spaces organize your work; tabs contain terminal panes; agents run in those panes. Herdcats lets you navigate that work from your phone. In a space, tap a pane in the pane switcher to open it. On iPhone, swipe right from the left edge to go back to the list.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-tui-or-core" className="faq-question">Should I connect with the TUI or Herdr Core?</h4>
        <p>Each saved connection uses one runtime. Pick it under <strong>Herdr</strong> in Connection Settings:</p>
        <ul>
        <li><strong>Auto</strong> (the default for new machines) checks the computer for both runtimes over SSH and saves an entry for each one it finds. If both are installed it connects with the TUI.</li>
        <li><strong>TUI</strong> runs the <code>herdr</code> command over SSH and uses Herdr&rsquo;s default session. Timeline, phone answers, and model controls need this runtime and Herdcats Bridge.</li>
        <li><strong>Herdr Core</strong> uses <code>hc connect</code>. Use it when the computer runs the Herdr desktop app or a standalone Herdr Core. It shows desktop spaces and tabs when their layout is available, plus <strong>Other terminals</strong> for terminals outside a space. It needs no Bridge.</li>
        </ul>
        <p>Herdr Core panes use the same terminal view, keys, Compose, dictation, and photos. Herdr Core can&rsquo;t receive raw text, so live typing sends key presses; for shifted symbols and non-ASCII characters the app asks you to use Compose. A Herdr Core connection never falls back to the TUI.</p>
        <p>A computer saved with both runtimes appears once, as <strong>TUI + Herdr Core</strong>, and opens with the runtime you used last. Long-press it on the connection screen to choose <strong>Connect with TUI</strong> or <strong>Connect with Herdr Core</strong>, or pick the runtime from the machine menu. Connections saved before Herdr Core support stay TUI.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-ipad-duo" className="faq-question">How do split panes work on iPad and the iPhone Duo?</h4>
        <p>On iPad and the unfolded iPhone Duo, Spaces and Agents show the list on the left and the selected pane beside it. On iPad the tab switcher is a pill at the bottom of the list; on the Duo it stays at the screen edge. Hide the list with the sidebar button, and swipe right from the leading edge to bring it back.</p>
        <p>To open two panes, use a row&rsquo;s menu (<strong>Open on Left</strong>, <strong>Open on Right</strong>, or <strong>Replace</strong>), the Split button, or drag a row onto the left or right half of the detail area. Each pane has its own header with an <strong>L</strong> or <strong>R</strong> tag, and the list shows the same tags next to open rows. Tap a pane to focus it; the keyboard moves with focus. Drag the divider to resize it to a third, half, or two thirds.</p>
        <p>In Spaces, expand a space to see its tabs and panes. Folding the Duo or narrowing the window keeps the pane you were using open. The iPhone layout is unchanged: one pane at a time, portrait only. iPad supports all orientations.</p>
        <div className="app-screenshots app-screenshots-wide">
          <AppScreenshot screen="ipad-split" alt="iPad in landscape with the Spaces list beside two conversation panes tagged L and R" caption="iPad: the Spaces list beside two active panes." />
          <AppScreenshot screen="duo-split" alt="Unfolded iPhone Duo with terminal output on the left and a Codex conversation on the right" caption="iPhone Duo, unfolded: terminal output beside a conversation." />
        </div>
        <p className="capture-note">Dark-mode simulator captures with sample sessions, 3 November 2026.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-when-should-i-use-live-compose-or-voice" className="faq-question">How do Timeline, Terminal, and Compose fit together?</h4>
        <p>Timeline and Terminal are two ways to read the same agent session. Compose is where you draft a message, and works with either view.</p>
        <ul>
        <li><strong>Timeline:</strong> read messages and tool activity in a conversation layout that follows your app theme. For supported agents, use the terminal or speech-bubble button at the top to switch views.</li>
        <li><strong>Terminal:</strong> see the agent&rsquo;s own terminal UI. Tap its output to type directly, or use the toolbar for special keys. After you scroll back into history, tap the round down-arrow button to jump to the newest output.</li>
        <li><strong>Compose:</strong> write and review a message before tapping Send. Tap the compose button in the toolbar to open it. Add photos with the attachment button.</li>
        <li><strong>Voice:</strong> tap the microphone to dictate, then the checkmark to finish recording. The transcript opens in Compose for you to edit and send.</li>
        </ul>
        <p><strong>Show Compose by Default</strong> keeps the message field visible. It is on by default; change it in Settings or the pane&rsquo;s menu. Turning it off gives you the compact toolbar when you are not editing a draft.</p>
        <div className="app-screenshots">
          <AppScreenshot screen="timeline-light" alt="Timeline in light mode with readable conversation messages, tool activity, and the composer" caption="Timeline follows your app&rsquo;s light or dark theme." />
          <AppScreenshot screen="terminal-compose" alt="Timeline conversation with an editable Compose draft at the bottom" caption="Compose lets you review a draft before sending." />
          <AppScreenshot screen="voice" alt="Herdcats recording bar with a checkmark to finish dictation" caption="Finish recording, review the transcript, then send." />
        </div>
        <p className="capture-note">Screenshots use demonstration sessions captured on 27–28 October 2026. Tap an image to open it at a larger size.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-what-is-the-timeline-helper-and-why-does-timeline-need-it" className="faq-question">What is Herdcats Bridge, and why does Timeline need it?</h4>
        <p>Timeline turns an agent session into a phone-friendly conversation: readable messages, tool activity, and images. A terminal pane can&#x27;t provide that — its output is a scrolling log. Herdcats Bridge (<code>herdcats-bridge</code>) is a small program on your SSH computer that reads the session&#x27;s structured transcript and sends it to your phone over the same SSH connection, only while Timeline is open.</p>
        <p>It is optional. Terminal, Compose, voice, and photos never need it, and Timeline asks before installing anything. Reading history requires no sudo, background service, or agent hooks. The current app installs Herdcats Bridge 0.5.0, supporting Claude, Codex, Agy (Antigravity CLI), Pi, and Cursor Agent (the Cursor CLI). Pi also requires a separately enabled Herdcats extension. Other agents keep using Terminal and Compose.</p>
        <p>On each SSH computer, tap <strong>Install</strong> in the Bridge setup sheet. Confirm the displayed host, account, port, and installation path. If you prefer, run the manual command shown in that sheet on the same computer, then tap <strong>Check again</strong>. To defer setup, choose <strong>Use Terminal for now</strong>.</p>
        <p>The current app requires Bridge 0.5.0 or later. For an older installation, choose <strong>Upgrade Herdcats Bridge</strong> when offered in the setup sheet or pane menu. Upgrades require an explicit action; manual replacements use <code>--replace</code>. Downloads are checksum-verified. See <a href="#troubleshooting-timeline-helper-missing-or-install-failed">Bridge troubleshooting</a> if setup fails.</p>
        <div className="app-screenshots app-screenshots-pair">
          <AppScreenshot screen="bridge-setup" alt="Herdcats Bridge setup sheet explaining Timeline with Install Herdcats Bridge and Use Terminal for now buttons" caption="Install Bridge only on the computer shown in the setup sheet." />
          <AppScreenshot screen="timeline-dark" alt="Herdcats Timeline showing the same conversation in dark mode" caption="Bridge sends the session history over your existing SSH connection." />
        </div>
        <p>If you enabled phone answers, remove them from the pane&rsquo;s phone-answer settings before deleting <code>~/.local/bin/herdcats-bridge</code>. Otherwise, deleting that binary removes Bridge. Phone-answer setup is a separate opt-in, explained below.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-pi" className="faq-question">How do I use Pi with Herdcats Bridge?</h4>
        <p>Install or upgrade to Bridge 0.5.0 on your SSH computer, then enable the Herdcats Pi extension in the Pi session you want to use. The integration supports Pi 1.4.0. Installing the Bridge binary does not install or enable the extension.</p>
        <p>Download <code>herdcats-pi-extension.tar.gz</code> and <code>SHA256SUMS</code> from the <a href="https://github.com/zhiyao/herdcats/releases/tag/herdcats-bridge-v0.5.0" target="_blank" rel="noopener noreferrer">Bridge 0.5.0 release</a>. Verify the archive against the checksums with <code>sha256sum</code> or <code>shasum -a 256</code>, then extract it. Keep <code>herdcats/index.ts</code> and <code>herdcats/runtime.mjs</code> together. Start Pi with <code>pi -e /absolute/path/to/herdcats/index.ts</code>, using your extracted path. For an existing session, place both files in <code>~/.pi/agent/extensions/herdcats/</code> (or <code>$PI_CODING_AGENT_DIR/extensions/herdcats/</code>), then use <code>/reload</code> in that Pi session. Return to Herdcats and tap <strong>Check again</strong>.</p>
        <p>Pi supports conversation history, streaming, plain messages, cancellation, model and thinking controls, and supported extension confirmation, selection, and text-input dialogs. Custom and editor dialogs, slash commands, authentication, and unsupported prompts stay in Terminal. Grant project trust at your computer before using phone controls.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-cursor" className="faq-question">Does Herdcats support Cursor Agent?</h4>
        <p>Yes. Bridge 0.5.0 supports Cursor Agent, the Cursor CLI, in a Herdr pane. Open that pane in Herdcats to read its conversation and send plain messages when the agent is idle and its composer is empty. This integration controls the CLI session running on your computer.</p>
        <p>Supported shell approvals offer <strong>Run once</strong> and <strong>Skip</strong>. Question forms are answered one question at a time. Model and effort controls are verified on Cursor build <code>2026.10.22-27dcf5f</code>; changes also become Cursor&rsquo;s defaults for new sessions. Slash commands and unsupported controls stay in Terminal.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-phone-answers" className="faq-question">How do I answer approvals and questions from my phone?</h4>
        <p>With a compatible Bridge, Timeline can show supported approval and question cards. Read the request, choose an option or enter an answer, then submit it. Available actions depend on the agent and the request. If a prompt cannot be verified or is unsupported, answer it in Terminal.</p>
        <p>Claude approvals and questions, and Codex approvals, require the optional phone-answer recording hook. When Timeline offers <strong>Set up phone answers</strong>, review the setup sheet and confirm. It adds a hook to that agent&rsquo;s settings on the connected computer and keeps a backup. Codex also asks you once at your desk to trust the new hook. Codex question cards do not require this hook. Agy and Cursor use supported native dialogs; Pi uses its separately enabled extension. They do not use the Claude/Codex recording hook.</p>
        <p>The hook records requests locally so your phone can display them; it does not approve them. Use <strong>Repair phone answers</strong> if offered for an outdated setup, or <strong>Remove phone answers</strong> to remove the Herdcats hook and delete its recorded requests. Other hooks are left in place.</p>
        <div className="app-screenshots app-screenshots-single">
          <AppScreenshot screen="approval" alt="A supported approval request in Timeline with response options" caption="Check the request before choosing an answer." />
        </div>
        </div>
        <div className="faq-item">
        <h4 id="using-app-model-controls" className="faq-question">Can I change the model or reasoning effort?</h4>
        <p>Bridge 0.5.0 includes model and reasoning-effort controls for supported Claude, Codex, Agy, and Cursor sessions, plus model and thinking controls for Pi with its extension enabled. Availability depends on the agent version and the controls reported by the connected Bridge.</p>
        <p>When available, choose from the models and effort levels reported by your agent. Changes require the agent to be idle with an empty input box. If the control is unavailable, wait for the current turn to finish or use Terminal. Codex changes apply to the current session; Claude and Cursor changes can become defaults for new sessions, Agy model choices may persist across sessions, and Pi changes apply to the connected native session.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-codex-shared-background-server" className="faq-question">Why does Codex Timeline ask me to turn off Codex&#x27;s shared background server?</h4>
        <p>Since Codex 0.157, Codex runs sessions inside one shared background server. That server only remembers the terminal that started it, so Herdr can&#x27;t tell which pane a Codex conversation belongs to. Herdcats never guesses: showing the wrong conversation is worse than showing none, so Timeline says the session isn&#x27;t identified.</p>
        <p>There are two ways to fix it:</p>
        <ol>
        <li>Start Codex with <code>codex --no-daemon</code> in the panes you want in Timeline.</li>
        <li>Turn the shared server off for all sessions: in a Codex pane&#x27;s Timeline, tap <strong>Turn off Codex&#x27;s shared daemon</strong>. Herdcats Bridge sets <code>daemon_auto_start = false</code> in <code>~/.codex/config.toml</code> (or <code>$CODEX_HOME/config.toml</code> if you set <code>CODEX_HOME</code>), keeps a backup, and changes nothing else in the file. If the server is already running, it stops it after you confirm. Codex sessions using it disconnect; start them again with <code>codex</code>, or <code>codex resume</code> to continue a conversation.</li>
        </ol>
        <p>Turning off the shared server gives up:</p>
        <ul>
        <li>Codex sessions surviving a closed terminal or dropped SSH connection. Herdr already keeps your panes running, so this is usually covered.</li>
        <li>Slightly faster Codex startup, since setup happens per session again.</li>
        <li>Features that need the shared server, such as forking an open conversation.</li>
        <li>Controlling those Codex sessions from ChatGPT&#x27;s Codex Remote. If you rely on Codex Remote, keep the server on and use <code>codex --no-daemon</code> only in the panes you want in Herdcats.</li>
        <li>Codex&#x27;s self-updating background package. The <code>codex</code> you installed is used instead.</li>
        </ul>
        <p>Undo any time with <code>codex features enable daemon_auto_start</code>.</p>
        <p>A brand-new Codex session appears in Timeline after its first message. Codex starts the session when you send one.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-does-herdcats-run-agents-on-my-iphone" className="faq-question">Does Herdcats run agents on my iPhone?</h4>
        <p>No. Agents run on your computer. Keep that computer running and reachable when you want to view their output or send input.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-can-i-send-photos" className="faq-question">Can I send photos?</h4>
        <p>Yes, to panes on the computer you connected to directly. Uploaded photos stay on that computer until you remove them manually; the app does not remove them automatically. Their location is <code>~/.cache/herdrcat/attachments</code>.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-what-happens-when-i-switch-apps-or-lock-my-phone" className="faq-question">What happens when I switch apps or lock my phone?</h4>
        <p>Herdcats pauses output refreshes while it is in the background. Return to the app to see refreshed output. Timeline keeps the conversation it already loaded for that pane while it reconnects. Leaving the app does not itself stop the agents running on your computer.</p>
        <p>If the connection drops, a status banner appears at the top. Output you already loaded stays on screen, with a card underneath that explains what happened and offers <strong>Retry</strong>. See <a href="#troubleshooting-offline-retry">Offline and Retry</a>.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-can-i-choose-a-different-herdr-session" className="faq-question">Can I choose a different Herdr session?</h4>
        <p>Not currently. TUI connections use Herdr&#x27;s default session, which must be running and accessible to the account you sign in with. Herdr Core connections show the terminals Herdr Core runs for that account.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-can-i-switch-between-computers-without-signing-in-to-each-one-on-my-phone" className="faq-question">How do I switch between computers?</h4>
        <p>Save an SSH connection for each computer in Herdcats, then choose one from the machine selector. Each connection has its own host, port, account, and credentials; the app connects directly to the selected computer. You can give saved connections names and arrange their order. Auto-connect uses the last-used computer.</p>
        <p>Install Herdr and enable SSH on each computer. If a computer has both the TUI and Herdr Core, it still appears once; see <a href="#using-app-tui-or-core">TUI or Herdr Core</a>. Bridge, phone-answer setup, photo uploads, and quota information belong to the computer you are connected to.</p>
        </div>
        <div className="faq-item">
        <h4 id="using-app-how-do-i-add-another-machine" className="faq-question">How do I add another machine?</h4>
        <p>Add a saved connection in Herdcats with that computer&rsquo;s SSH hostname or IP address, port, username, and password or supported private key. Give it a name if you want an easier way to recognize it, then connect and verify its host key.</p>
        <p>Follow <a href="#connect">How to connect</a> for each computer. Herdr&rsquo;s own connected-machine list is separate from Herdcats&rsquo; saved SSH connections.</p>
        </div>
        </div>
        </section>

        <section id="connect" aria-labelledby="connect-title" className="guide-card connection-guide">
        <h2 id="connect-title">How to connect</h2>
        <ol className="connection-steps">
        <li>Set up Herdr on your computer with the account you will use in Herdcats: install the <a href="https://herdr.dev">Herdr TUI</a> and start its default session, or run <a href="https://github.com/herdrdev/herdr-core">Herdr Core</a>, for example through the Herdr desktop app.</li>
        <li>Enable SSH access using the setup guide for your computer below. On a Mac, follow <a href="#macos-setup">Enable Remote Login</a>.</li>
        <li>Connect your iPhone and computer to a network where they can reach each other. Tailscale is recommended.</li>
        <li>In Herdcats, leave <strong>Herdr</strong> on <strong>Auto</strong> (or choose TUI or Herdr Core), then enter the hostname or IP address, SSH port, username, and password or supported private key.</li>
        <li>Compare the server fingerprint with one obtained directly from your computer or its administrator, then approve it only if they match.</li>
        </ol>
        <p className="connection-note">Using more than one computer? Save a separate SSH connection for each, then switch with the machine selector.</p>
        </section>
        {/* TAB 1: macOS */}
        <section className="tab-pane" id="macos-setup">
            <div className="guide-card">
              <h2>Setting up SSH on macOS</h2>
              <p className="card-desc">
                Follow these steps to enable SSH access on your Mac and generate an ed25519 key for Herdcats.
              </p>
              <p className="prereq-text">
                Before you start: install <a href="https://herdr.dev" target="_blank" rel="noopener noreferrer">Herdr</a> on
                the Mac and keep a Herdr session running, or run the Herdr desktop app for Herdr Core. Herdcats drives the <code>herdr</code> or <code>hc</code> command over SSH.
              </p>

              <ol className="step-list">
                <li className="step-item">
                  <div className="step-num">1</div>
                  <div className="step-body">
                    <h3 id="macos-setup-enable-remote-login">Enable Remote Login</h3>
                    <p>Open <strong>System Settings</strong> on your Mac:</p>
                    <p className="path-text">Apple Menu () → System Settings → General → Sharing → turn on <strong>Remote Login</strong>.</p>
                    <p className="tip-text">Ensure your user account is permitted under &ldquo;Allow access for&rdquo;.</p>
                  </div>
                </li>

                <li className="step-item">
                  <div className="step-num">2</div>
                  <div className="step-body">
                    <h3 id="macos-setup-generate-an-ed25519-key-authorize-it">Generate an Ed25519 Key &amp; Authorize It</h3>
                    <p>Open Terminal on your Mac and run this one-line command:</p>
                    <div className="code-box">
                      <pre><code>ssh-keygen -t ed25519 -f ~/.ssh/herdcats_key &amp;&amp; cat ~/.ssh/herdcats_key.pub &gt;&gt; ~/.ssh/authorized_keys &amp;&amp; chmod 700 ~/.ssh &amp;&amp; chmod 600 ~/.ssh/authorized_keys</code></pre>
                      <button
                        type="button"
                        className="copy-btn"
                        onClick={() => copyToClipboard('ssh-keygen -t ed25519 -f ~/.ssh/herdcats_key && cat ~/.ssh/herdcats_key.pub >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys', 'mac-gen')}
                      >
                        {copiedIndex === 'mac-gen' ? '✓ Copied' : 'Copy'}
                      </button>
                    </div>
                  </div>
                </li>

                <li className="step-item">
                  <div className="step-num">3</div>
                  <div className="step-body">
                    <h3 id="macos-setup-transfer-the-private-key-to-herdcats">Transfer the Private Key to Herdcats</h3>
                    <p>You can bring the private key into Herdcats using either method:</p>
                    <div className="sub-options">
                      <div className="sub-option">
                        <strong>Method A (AirDrop / Files):</strong>
                        <p>AirDrop <code>~/.ssh/herdcats_key</code> (without <code>.pub</code>) to your iPhone and save to Files. In Herdcats, tap <strong>Import…</strong> and select it.</p>
                      </div>
                      <div className="sub-option">
                        <strong>Method B (Clipboard):</strong>
                        <p>Copy to clipboard: <code>cat ~/.ssh/herdcats_key | pbcopy</code>. Paste directly into the private key field in Herdcats.</p>
                      </div>
                    </div>
                  </div>
                </li>

                <li className="step-item">
                  <div className="step-num">4</div>
                  <div className="step-body">
                    <h3 id="macos-setup-find-host-username">Find Host &amp; Username</h3>
                    <p>In Terminal on your Mac, find your connection details:</p>
                    <ul className="info-bullets">
                      <li><strong>Username:</strong> Run <code>whoami</code> (e.g. <code>alice</code>).</li>
                      <li>
                        <strong>Host:</strong> If using Tailscale (recommended), run <code>tailscale ip -4</code> or use your MagicDNS hostname (e.g. <code>mac-mini.tailnet-name.ts.net</code>). Otherwise use your local network IP (e.g. <code>192.168.1.50</code>).
                      </li>
                      <li><strong>Port:</strong> Default is <code>22</code>.</li>
                    </ul>
                  </div>
                </li>
              </ol>
            </div>
          </section>

        {/* TAB 2: Linux */}
        <section className="tab-pane" id="linux-setup">
            <div className="guide-card">
              <h2>Setting up SSH on Linux</h2>
              <p className="card-desc">
                Instructions for Ubuntu, Debian, Fedora, Arch Linux, and remote cloud VMs (AWS, GCP, Hetzner).
              </p>

              <ol className="step-list">
                <li className="step-item">
                  <div className="step-num">1</div>
                  <div className="step-body">
                    <h3 id="linux-setup-ensure-openssh-server-is-installed-running">Ensure OpenSSH Server is Installed &amp; Running</h3>
                    <p>Run the package manager commands for your distribution:</p>
                    <div className="code-box">
                      <pre><code>{`# Ubuntu / Debian
sudo apt update && sudo apt install openssh-server -y
sudo systemctl enable --now ssh

# Fedora / RHEL
sudo dnf install openssh-server -y
sudo systemctl enable --now sshd

# Arch Linux
sudo pacman -S openssh
sudo systemctl enable --now sshd`}</code></pre>
                      <button
                        type="button"
                        className="copy-btn"
                        onClick={() => copyToClipboard('sudo apt update && sudo apt install openssh-server -y && sudo systemctl enable --now ssh', 'linux-install')}
                      >
                        {copiedIndex === 'linux-install' ? '✓ Copied' : 'Copy'}
                      </button>
                    </div>
                  </div>
                </li>

                <li className="step-item">
                  <div className="step-num">2</div>
                  <div className="step-body">
                    <h3 id="linux-setup-generate-authorize-key">Generate &amp; Authorize Key</h3>
                    <p>Generate an ed25519 keypair and ensure correct permissions:</p>
                    <div className="code-box">
                      <pre><code>ssh-keygen -t ed25519 -f ~/.ssh/herdcats_key &amp;&amp; cat ~/.ssh/herdcats_key.pub &gt;&gt; ~/.ssh/authorized_keys &amp;&amp; chmod 700 ~/.ssh &amp;&amp; chmod 600 ~/.ssh/authorized_keys</code></pre>
                      <button
                        type="button"
                        className="copy-btn"
                        onClick={() => copyToClipboard('ssh-keygen -t ed25519 -f ~/.ssh/herdcats_key && cat ~/.ssh/herdcats_key.pub >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys', 'linux-keygen')}
                      >
                        {copiedIndex === 'linux-keygen' ? '✓ Copied' : 'Copy'}
                      </button>
                    </div>
                  </div>
                </li>

                <li className="step-item">
                  <div className="step-num">3</div>
                  <div className="step-body">
                    <h3 id="linux-setup-check-firewall-herdr-binary-location">Check Firewall &amp; herdr Binary Location</h3>
                    <p>If you use a firewall like UFW:</p>
                    <div className="code-box">
                      <pre><code>sudo ufw allow ssh</code></pre>
                    </div>
                    <p style={{ marginTop: '10px' }}>
                      Ensure the <code>herdr</code> CLI binary is installed and reachable in your user&rsquo;s <code>PATH</code>, <code>~/.local/bin</code>, or <code>/usr/local/bin</code>.
                    </p>
                  </div>
                </li>
              </ol>
            </div>
          </section>

        {/* TAB 3: Windows / WSL */}
        <section className="tab-pane" id="windows-setup">
            <div className="guide-card">
              <h2>Setting up SSH on Windows / WSL</h2>
              <p className="card-desc">
                For developers working on Windows, connecting via Windows Subsystem for Linux (WSL2) is the recommended path.
              </p>

              <ol className="step-list">
                <li className="step-item">
                  <div className="step-num">1</div>
                  <div className="step-body">
                    <h3 id="windows-setup-option-a-wsl-2-recommended">Option A: WSL 2 (Recommended)</h3>
                    <p>Open your WSL terminal (e.g. Ubuntu) and configure OpenSSH server:</p>
                    <div className="code-box">
                      <pre><code>{`sudo apt install openssh-server -y
sudo service ssh start
ssh-keygen -t ed25519 -f ~/.ssh/herdcats_key
cat ~/.ssh/herdcats_key.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`}</code></pre>
                      <button
                        type="button"
                        className="copy-btn"
                        onClick={() => copyToClipboard('sudo apt install openssh-server -y && sudo service ssh start && ssh-keygen -t ed25519 -f ~/.ssh/herdcats_key && cat ~/.ssh/herdcats_key.pub >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys', 'wsl-setup')}
                      >
                        {copiedIndex === 'wsl-setup' ? '✓ Copied' : 'Copy'}
                      </button>
                    </div>
                  </div>
                </li>

                <li className="step-item">
                  <div className="step-num">2</div>
                  <div className="step-body">
                    <h3 id="windows-setup-option-b-native-windows-openssh-server">Option B: Native Windows OpenSSH Server</h3>
                    <p>Open PowerShell as Administrator:</p>
                    <div className="code-box">
                      <pre><code>{`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'`}</code></pre>
                      <button
                        type="button"
                        className="copy-btn"
                        onClick={() => copyToClipboard('Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType \'Automatic\'', 'win-native')}
                      >
                        {copiedIndex === 'win-native' ? '✓ Copied' : 'Copy'}
                      </button>
                    </div>
                    <p style={{ marginTop: '8px' }}>
                      Authorize your public key in <code>%USERPROFILE%\.ssh\authorized_keys</code>.
                    </p>
                  </div>
                </li>
              </ol>
            </div>
          </section>

        {/* TAB 4: SSH Keys & Security */}
        <section className="tab-pane" id="ssh-keys">
            <div className="guide-card">
              <h2>SSH Key Management &amp; Security Architecture</h2>
              <p className="card-desc">
                Understanding how Herdcats handles authentication, key masking, and Keychain isolation.
              </p>

              <div className="feature-grid">
                <div className="feature-cell">
                  <h3 id="ssh-keys-why-ed25519">Why Ed25519?</h3>
                  <p>
                    Ed25519 is the key type Herdcats supports. The keys are short and quick to generate, and
                    OpenSSH has used them by default for years.
                  </p>
                </div>
                <div className="feature-cell">
                  <h3 id="ssh-keys-passphrase-notice">Passphrase Notice</h3>
                  <p>
                    Herdcats supports passphrase-protected OpenSSH ed25519 keys using AES-128-CTR or AES-256-CTR
                    with bcrypt (1–256 rounds). Set a passphrase when ssh-keygen prompts, then enter it when importing your key. Optionally remember
                    it on this device to reconnect after restarting the app.
                  </p>
                </div>
                <div className="feature-cell">
                  <h3 id="ssh-keys-on-device-keychain">On-Device Keychain</h3>
                  <p>
                    Remembered passwords and keys are stored exclusively in the iOS Keychain on your physical device.
                    Private keys and key passphrases stay on your device. SSH uses the key to sign authentication requests; passwords are sent only through the encrypted SSH connection.
                  </p>
                </div>
                <div className="feature-cell">
                  <h3 id="ssh-keys-shoulder-surfing-protection">Shoulder-Surfing Protection</h3>
                  <p>
                    Herdcats masks private key text by default, displaying only the last 2 lines for verification.
                    Tap the <strong>Show</strong> toggle if you need to inspect the full key.
                  </p>
                </div>
              </div>
            </div>
          </section>

        {/* TAB 5: Troubleshooting */}
        <section className="tab-pane" id="troubleshooting">
            <div className="guide-card">
              <h2>Troubleshooting &amp; Common Issues</h2>
              <p className="card-desc">
                Quick resolutions for connection, authentication, and environment issues.
              </p>

              <div className="faq-list">
                <div className="faq-item">
                  <h3 id="troubleshooting-authentication-failed-check-username-and-password-key"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>&ldquo;Authentication failed — check username and password/key&rdquo;</span></h3>
                  <p>
                    The SSH server rejected authentication (<code>allAuthenticationOptionsFailed</code>).
                  </p>
                  <ul>
                    <li>Verify the matching public key shown in Herdcats is in <code>~/.ssh/authorized_keys</code>.</li>
                    <li>
                      Check permissions on your remote host:
                      <br />
                      <code>chmod 700 ~/.ssh &amp;&amp; chmod 600 ~/.ssh/authorized_keys</code>
                    </li>
                    <li>Ensure you imported the <strong>private key</strong> (e.g. <code>herdcats_key</code>), not the <code>.pub</code> public key.</li>
                  </ul>
                </div>

                <div className="faq-item">
                  <h3 id="troubleshooting-host-key-verification-failed-changed"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>&ldquo;Host key verification failed / changed&rdquo;</span></h3>
                  <p>
                    Herdcats pins remote host key fingerprints in Keychain on first connect (Trust On First Use). If your server was reinstalled or rebuilt, the key will fail closed to prevent MITM attacks. Verify the change directly with your computer or its administrator before restoring access. The app shows both the previously approved and new fingerprints. After verifying the new fingerprint through a trusted channel, confirm verification and choose “Replace Approved Key and Connect” to update trust for that hostname and port.
                  </p>
                </div>

                <div className="faq-item">
                  <h3 id="troubleshooting-connection-timeout-host-unreachable"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>&ldquo;Timed out reaching the host&rdquo; / Host unreachable</span></h3>
                  <p>
                    Herdcats waits 10 seconds for the SSH server to answer. If nothing answers, it shows &ldquo;Timed out reaching the host — check the IP address and that SSH (Remote Login) is enabled on the machine.&rdquo;
                  </p>
                  <ul>
                    <li>Check the hostname or IP address in Connection Settings. With Tailscale, the MagicDNS name from the Tailscale app is the most reliable choice.</li>
                    <li>Confirm SSH is on: on a Mac, <a href="#macos-setup-enable-remote-login">Remote Login</a>; on Linux, <code>systemctl status ssh</code> (or <code>sshd</code>).</li>
                    <li>Make sure the computer is awake and both devices are connected to Tailscale, or on the same Wi-Fi subnet without Tailscale.</li>
                    <li>&ldquo;Connection refused&rdquo; is different: the computer answered, but nothing is listening on that port. Check the port and that SSH is running.</li>
                  </ul>
                </div>

                <div className="faq-item">
                  <h3 id="troubleshooting-herdr-command-not-found"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>&ldquo;herdr: command not found&rdquo;</span></h3>
                  <p>
                    For TUI connections, Herdcats looks for <code>herdr</code> in <code>PATH</code>, <code>~/.local/bin</code>, <code>/opt/homebrew/bin</code>, and <code>/usr/local/bin</code>. Ensure Herdr is installed on the remote machine. If the machine runs the Herdr desktop app instead, see the next item.
                  </p>
                </div>

                <div className="faq-item">
                  <h3 id="troubleshooting-core-only-mac"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>&ldquo;Herdr was not found&rdquo; on a Mac that runs the Herdr desktop app</span></h3>
                  <p>
                    The desktop app installs Herdr Core (<code>hc</code>), not the Herdr TUI. A connection saved as TUI, including every connection saved before Herdr Core support, looks only for <code>herdr</code> and reports &ldquo;SSH worked. Herdr was not found.&rdquo; Installing the TUI doesn&rsquo;t help: it starts a separate Herdr that doesn&rsquo;t show the desktop app&rsquo;s terminals.
                  </p>
                  <p>
                    Workaround: open that connection&rsquo;s settings, set <strong>Herdr</strong> to <strong>Herdr Core</strong> (or <strong>Auto</strong>), and tap <strong>Connect</strong>. Herdcats adds a Herdr Core entry for the same machine and sign-in, and keeps the TUI entry. The machine then shows <strong>TUI + Herdr Core</strong> and opens with the runtime you used last. The reverse also happens: a Herdr Core connection to a machine with only the TUI can fail with a generic closed-connection error; switch it to TUI or Auto the same way.
                  </p>
                </div>

                <div className="faq-item">
                  <h3 id="troubleshooting-offline-retry"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>The app shows an offline card with Retry</span></h3>
                  <p>
                    The SSH connection dropped or the computer stopped answering. The banner at the top shows the connection status; the card under the content explains what failed. Output and Timeline messages you already loaded stay visible, and drafts in Compose are kept.
                  </p>
                  <ul>
                    <li>Tap <strong>Retry</strong> once the computer is reachable again. If Retry keeps failing, work through <a href="#troubleshooting-connection-timeout-host-unreachable">Timed out reaching the host</a>.</li>
                    <li>A running-cat loader means Herdcats is still waiting for a reply. An error with Retry appears only after a request fails.</li>
                    <li>Quota shows setup steps when <code>quota-axi</code> isn&rsquo;t installed, and an error with Retry when it fails.</li>
                  </ul>
                </div>

                <div className="faq-item">
                  <h3 id="troubleshooting-timeline-helper-missing-or-install-failed"><TriangleAlert className="warn-icon" size={18} strokeWidth={2.25} aria-hidden="true" /><span>&ldquo;Timeline says Herdcats Bridge is missing or could not be installed&rdquo;</span></h3>
                  <p>
                    Timeline needs optional Herdcats Bridge (<code>herdcats-bridge</code>) on the computer your phone connects to directly — without it, that view falls back to Terminal, which stays fully usable. Tap <strong>Install</strong> in the setup sheet, or copy the manual install command shown there and run it on that computer, then tap <strong>Check again</strong>. For an existing installation, tap <strong>Upgrade</strong>; manual upgrades require <code>--replace</code>. If installation cannot be verified, choose <strong>Check installation</strong>; Terminal and Compose keep working without Herdcats Bridge.
                  </p>
                </div>
                <div className="faq-item">
                  <h4 id="troubleshooting-codex-session-not-identified" className="faq-question">Timeline says &ldquo;Send a message to start&rdquo; or &ldquo;Codex session not identified&rdquo;</h4>
                  <p><strong>Send a message to start:</strong> Codex starts a session only when you send its first message. Send one, and Timeline appears once Codex replies.</p>
                  <p><strong>Codex session not identified:</strong> if Timeline says the shared background server is running, follow <a href="#using-app-codex-shared-background-server">Codex background server</a>, then restart Codex in that pane.</p>
                  <p>If the server is already off, the pane&#x27;s session reference is invalid or matches more than one session. Restart Codex in that pane, then tap <strong>Check again</strong>.</p>
                  <p>Codex sessions started before you turned the server off keep using it, and stop working once it is stopped. Quit Codex in that pane and run <code>codex resume</code> to continue the conversation in Timeline.</p>
                </div>
              </div>
            </div>
          </section>

        </div>
      </main>

      <SiteFooter />

      {/* Styles */}

    </div>
  );
}
