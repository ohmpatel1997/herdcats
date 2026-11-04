import { screenshotUrl } from '@/lib/screenshots';
import { SitePage } from '@/components/SitePage';
import styles from './page.module.css';

export const metadata = {
  title: 'Herdcats — Features',
  description: 'Explore Herdcats spaces, agents, terminal, quotas, Compose and voice on iPhone, plus two panes side by side on iPad and the unfolded iPhone Duo.',
};

const screens = [
  ['01-spaces', 'Spaces', 'See your workspaces and which agents need attention.'],
  ['02-agents', 'Agents', 'Check blocked, working and finished agents across projects.'],
  ['03-pane', 'Live terminal', 'Read real ANSI terminal output, jump back to the newest line, and send input to your agent.'],
  ['04-keys', 'Terminal keys', 'Use arrows, function keys and modifiers from your iPhone.'],
  ['05-agent-pane', 'Agent pane', 'Open an agent’s pane and continue where you left off.'],
  ['06-quota', 'Model quotas', 'Track remaining usage and reset windows across providers.'],
  ['07-connect', 'Connection settings', 'Connect directly to your machine over SSH or Tailscale.'],
  ['08-settings', 'Settings', 'Choose your appearance, pane preferences and local draft storage.'],
  ['09-compose', 'Compose', 'Draft and review a message before sending it to your agent.'],
  ['10-voice', 'Voice', 'Dictate a message, then review it before sending.'],
];

const largeScreens = [
  ['ipad-split', 'iPad', 1400, 1050, 'Keep the Spaces list open beside two live panes. Each pane has its own header, an L or R tag, and its own composer.'],
  ['duo-split', 'iPhone Duo, unfolded', 1400, 985, 'Open terminal output on one side and a conversation on the other. Fold the phone and the pane you were using stays open.'],
] as const;

export default function FeaturesPage() {
  return (
    <SitePage current="features" title="Your agents, from your pocket">
      <p className={styles.intro}>
        Manage workspaces, follow your agents, and send your next instruction over SSH.
        Connect to the Herdr TUI or to Herdr Core, the runtime behind the Herdr desktop app.
        Explore the features below with sample sessions from the iPhone app.
        Use the theme switch to see each feature in light or dark mode.
      </p>
      <div className={styles.grid}>
        {screens.map(([id, title, description]) => (
          <figure className={styles.card} key={id}>
            <figcaption>
              <h2>{title}</h2>
              <p>{description}</p>
            </figcaption>
            {(['dark', 'light'] as const).map((mode) => {
              const src = screenshotUrl(id, mode === 'light');
              return (
                <a className={styles[mode]} href={src} key={mode} aria-label={`View ${title} in ${mode} mode at full size`}>
                  <img src={src} width={1320} height={2868} loading="lazy" alt={`${title} in ${mode} mode. ${description}`} />
                </a>
              );
            })}
          </figure>
        ))}
      </div>
      <section className={styles.large} aria-labelledby="large-screens">
        <h2 id="large-screens">Two panes on large screens</h2>
        <p className={styles.intro}>
          On iPad and the unfolded iPhone Duo, Spaces and Agents show the list beside the selected pane.
          Open a second pane next to the first from a row&rsquo;s menu, the Split button, or by dragging a row
          onto the left or right half. Drag the divider to resize. These captures are dark mode only.
        </p>
        {largeScreens.map(([id, title, width, height, description]) => {
          const src = `/assets/app/${id}.webp`;
          return (
            <figure className={styles.wideCard} key={id}>
              <figcaption>
                <h3>{title}</h3>
                <p>{description}</p>
              </figcaption>
              <a href={src} aria-label={`View the ${title} split view at full size`}>
                <img src={src} width={width} height={height} loading="lazy" alt={`${title} split view with two panes side by side. ${description}`} />
              </a>
            </figure>
          );
        })}
      </section>
    </SitePage>
  );
}
