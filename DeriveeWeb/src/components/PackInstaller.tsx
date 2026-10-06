import { useEffect, useState, useRef } from 'preact/hooks';
import type { InstalledPackState, InstallerStage, WorkerToMainMessage } from '../types/pack';
import {
  checkFullPackInstallState,
  saveInstalledPackState,
  isOpfsSupported,
  setPackDismissed,
} from '../utils/opfs';
import { forceRelogin, RELOGIN_FALLBACK_MESSAGE } from '../utils/relogin';
import { PackInstallWatchdog } from '../utils/tabSuspension';
import {
  isPackUpdateAvailable,
  fetchPackInfo,
  setTrackedCityPackVersion,
  type PackInfo,
} from '../utils/packUpdates';

interface PackInstallerProps {
  onPackStateChange?: (state: InstalledPackState | null) => void;
  isOnline: boolean;
  isDismissed?: boolean;
  isExpanded?: boolean;
  onDismiss?: () => void;
  onToggleExpand?: () => void;
  onInstallSuccess?: () => void;
}

export function PackInstaller({
  onPackStateChange,
  isOnline,
  isDismissed = false,
  isExpanded = false,
  onDismiss,
  onToggleExpand,
  onInstallSuccess,
}: PackInstallerProps) {
  const [internalExpanded, setInternalExpanded] = useState<boolean>(false);
  const effectiveExpanded = onToggleExpand ? isExpanded : internalExpanded;

  const handleToggleExpand = () => {
    if (onToggleExpand) {
      onToggleExpand();
    } else {
      setInternalExpanded((prev) => !prev);
    }
  };

  const handleDismiss = () => {
    onDismiss?.();
  };
  const [authStatus, setAuthStatus] = useState<'checking' | 'authenticated' | 'unauthenticated'>('checking');
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [packState, setPackState] = useState<InstalledPackState | null>(null);
  const [isVerifyingDisk, setIsVerifyingDisk] = useState<boolean>(true);
  const [isInstalling, setIsInstalling] = useState<boolean>(false);
  const [installStage, setInstallStage] = useState<InstallerStage | null>(null);
  const [progress, setProgress] = useState<{
    loadedBytes?: number;
    totalBytes?: number;
    filesWritten?: number;
    totalFiles?: number;
    currentFile?: string;
    percent?: number;
    message?: string;
  }>({});
  const [errorMessage, setErrorMessage] = useState<{ code?: number; text: string } | null>(null);
  const [reloginError, setReloginError] = useState<string | null>(null);
  const [wakeLockActive, setWakeLockActive] = useState<boolean>(false);

  const wakeLockRef = useRef<WakeLockSentinel | null>(null);
  const workerRef = useRef<Worker | null>(null);
  const watchdogRef = useRef<PackInstallWatchdog | null>(null);

  type UpdateStatus = 'idle' | 'checking' | 'available' | 'up-to-date' | 'error';
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus>('idle');
  const [availableUpdate, setAvailableUpdate] = useState<PackInfo | null>(null);
  const [updateError, setUpdateError] = useState<string | null>(null);

  const checkForUpdates = async (slugToTest?: string) => {
    const slug = slugToTest || packState?.slug;
    if (!slug) return;
    if (!isOnline) {
      setUpdateStatus('idle');
      return;
    }

    setUpdateStatus('checking');
    setUpdateError(null);
    try {
      const info = await fetchPackInfo(slug);
      if (!info) {
        setUpdateStatus('error');
        setUpdateError("Couldn't check for pack updates");
        return;
      }

      const installedVersion = Number(packState?.version ?? 0);
      if (isPackUpdateAvailable(installedVersion, info)) {
        setAvailableUpdate(info);
        setUpdateStatus('available');
      } else {
        setAvailableUpdate(null);
        setUpdateStatus('up-to-date');
      }
    } catch {
      setUpdateStatus('error');
      setUpdateError("Couldn't check for pack updates");
    }
  };

  // 1. Check OPFS for already installed pack on every launch
  useEffect(() => {
    let isMounted = true;
    async function checkDisk() {
      setIsVerifyingDisk(true);
      try {
        const state = await checkFullPackInstallState('nyc');
        if (isMounted) {
          setPackState(state);
          onPackStateChange?.(state);
          if (state && isOnline) {
            checkForUpdates(state.slug);
          }
        }
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn('[PackInstaller] Disk verification check failed:', err);
      } finally {
        if (isMounted) {
          setIsVerifyingDisk(false);
        }
      }
    }
    checkDisk();
    return () => {
      isMounted = false;
    };
  }, []);

  // 1b. Check for pack updates when online transitions or pack state updates
  useEffect(() => {
    if (packState && isOnline && !isInstalling) {
      checkForUpdates(packState.slug);
    } else if (!isOnline) {
      setUpdateStatus('idle');
    }
  }, [packState?.slug, packState?.version, isOnline, isInstalling]);

  // 1c. Check for pack updates on returning to foreground
  useEffect(() => {
    const handleForeground = () => {
      if (
        typeof document !== 'undefined' &&
        document.visibilityState === 'visible' &&
        isOnline &&
        packState &&
        !isInstalling
      ) {
        checkForUpdates(packState.slug);
      }
    };

    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', handleForeground);
    }
    if (typeof window !== 'undefined') {
      window.addEventListener('focus', handleForeground);
    }
    return () => {
      if (typeof document !== 'undefined') {
        document.removeEventListener('visibilitychange', handleForeground);
      }
      if (typeof window !== 'undefined') {
        window.removeEventListener('focus', handleForeground);
      }
    };
  }, [packState?.slug, packState?.version, isOnline, isInstalling]);

  // 2. Check Auth status via /api/me
  useEffect(() => {
    let isMounted = true;
    async function checkAuth() {
      try {
        const res = await fetch('/api/me', {
          credentials: 'include',
        });
        if (!isMounted) return;

        if (res.status === 200) {
          const data = await res.json() as { email?: string };
          setUserEmail(data.email || 'Authenticated Tester');
          setAuthStatus('authenticated');
        } else if (res.status === 401) {
          setAuthStatus('unauthenticated');
        } else {
          // If offline or non-401, check if we have offline pack
          setAuthStatus(isOnline ? 'unauthenticated' : 'authenticated');
        }
      } catch (err) {
        if (!isMounted) return;
        // eslint-disable-next-line no-console
        console.warn('[PackInstaller] /api/me check network error:', err);
        // If offline and pack exists, keep user in functional offline state
        setAuthStatus(isOnline ? 'unauthenticated' : 'authenticated');
      }
    }

    checkAuth();
    return () => {
      isMounted = false;
    };
  }, [isOnline]);

  // Cleanup worker, wake lock, and watchdog on unmount
  useEffect(() => {
    return () => {
      if (workerRef.current) {
        workerRef.current.terminate();
        workerRef.current = null;
      }
      if (wakeLockRef.current) {
        wakeLockRef.current.release().catch(() => {});
        wakeLockRef.current = null;
      }
      if (watchdogRef.current) {
        watchdogRef.current.stop();
        watchdogRef.current = null;
      }
    };
  }, []);

  // Screen Wake Lock helper
  const acquireWakeLock = async () => {
    if ('wakeLock' in navigator && !wakeLockRef.current) {
      try {
        const lock = await navigator.wakeLock.request('screen');
        wakeLockRef.current = lock;
        setWakeLockActive(true);
        // eslint-disable-next-line no-console
        console.info('[PackInstaller] Screen wake lock acquired');
        lock.addEventListener('release', () => {
          if (wakeLockRef.current === lock) {
            setWakeLockActive(false);
            wakeLockRef.current = null;
          }
        });
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn('[PackInstaller] Wake lock request rejected (continuing install):', err);
      }
    }
  };

  const releaseWakeLock = async () => {
    if (wakeLockRef.current) {
      const lock = wakeLockRef.current;
      wakeLockRef.current = null;
      setWakeLockActive(false);
      try {
        await lock.release();
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn('[PackInstaller] Wake lock release error:', err);
      }
    }
  };

  // Re-acquire wake lock and monitor background suspension during pack install
  useEffect(() => {
    let lastHidden = 0;

    const handleVisibilityChange = () => {
      if (typeof document === 'undefined') return;

      if (document.visibilityState === 'hidden') {
        lastHidden = Date.now();
      } else if (document.visibilityState === 'visible') {
        const suspendedMs = lastHidden > 0 ? Date.now() - lastHidden : 0;
        lastHidden = 0;

        if (isInstalling) {
          acquireWakeLock();
          watchdogRef.current?.handleResume(suspendedMs);
        }
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [isInstalling]);

  const startInstall = async (expectedTotalBytes?: number) => {
    setErrorMessage(null);
    setIsInstalling(true);
    setInstallStage('downloading');
    setProgress({
      loadedBytes: 0,
      totalBytes: expectedTotalBytes || 29688421,
      percent: 0,
      message: 'Connecting to Cloudflare edge...',
    });

    await acquireWakeLock();

    const watchdog = new PackInstallWatchdog(20_000, async (diagnostic) => {
      if (workerRef.current) {
        workerRef.current.terminate();
        workerRef.current = null;
      }
      await releaseWakeLock();
      setIsInstalling(false);
      setInstallStage(null);
      setErrorMessage({ text: diagnostic });
    });
    watchdogRef.current = watchdog;
    watchdog.start();

    try {
      if (workerRef.current) {
        workerRef.current.terminate();
      }

      // Instantiate installer worker
      const worker = new Worker(
        new URL('../workers/pack-installer.worker.ts', import.meta.url),
        { type: 'module' }
      );
      workerRef.current = worker;

      worker.onmessage = async (event: MessageEvent<WorkerToMainMessage>) => {
        const data = event.data;

        if (data.type === 'PROGRESS') {
          watchdogRef.current?.recordProgress();
          setInstallStage(data.stage);
          setProgress({
            loadedBytes: data.loadedBytes,
            totalBytes: data.totalBytes,
            filesWritten: data.filesWritten,
            totalFiles: data.totalFiles,
            currentFile: data.currentFile,
            percent: data.percent,
            message: data.message,
          });
        } else if (data.type === 'SUCCESS') {
          watchdogRef.current?.stop();
          watchdogRef.current = null;
          saveInstalledPackState(data.packState);
          setPackState(data.packState);
          setTrackedCityPackVersion(data.packState.slug, data.packState.version);
          onPackStateChange?.(data.packState);
          setIsInstalling(false);
          setInstallStage(null);
          setPackDismissed(false);
          setAvailableUpdate(null);
          setUpdateStatus('up-to-date');
          onInstallSuccess?.();
          await releaseWakeLock();
          worker.terminate();
          workerRef.current = null;
        } else if (data.type === 'ERROR') {
          watchdogRef.current?.stop();
          watchdogRef.current = null;
          setIsInstalling(false);
          setInstallStage(null);
          setErrorMessage({ code: data.code, text: data.message });
          await releaseWakeLock();
          worker.terminate();
          workerRef.current = null;
        }
      };

      worker.onerror = async (err) => {
        watchdogRef.current?.stop();
        watchdogRef.current = null;
        // eslint-disable-next-line no-console
        console.error('[PackInstaller] Worker runtime error:', err);
        setIsInstalling(false);
        setInstallStage(null);
        setErrorMessage({
          text: `Worker execution failure: ${err.message || 'Unknown worker error'}`,
        });
        await releaseWakeLock();
        worker.terminate();
        workerRef.current = null;
      };

      worker.postMessage({
        type: 'START_INSTALL',
        slug: 'nyc',
        packUrl: '/api/pack',
      });
    } catch (err) {
      watchdogRef.current?.stop();
      watchdogRef.current = null;
      setIsInstalling(false);
      setInstallStage(null);
      await releaseWakeLock();
      setErrorMessage({
        text: `Failed to initialize pack installer worker: ${(err as Error).message}`,
      });
    }
  };

  const handleReinstall = async () => {
    if (confirm('Re-download and verify the NYC transit pack from scratch?')) {
      await startInstall();
    }
  };

  const handleStartUpdate = async () => {
    if (!availableUpdate || !packState) return;
    await startInstall(availableUpdate.size);
  };

  const formatBytes = (bytes?: number, decimal: boolean = false) => {
    if (!bytes || bytes <= 0) return '0 B';
    const divisor = decimal ? 1000 : 1024;
    const mbDivisor = decimal ? 1_000_000 : 1024 * 1024;
    if (bytes >= mbDivisor) {
      return `${(bytes / mbDivisor).toFixed(1)} MB`;
    }
    if (bytes >= divisor) {
      return `${(bytes / divisor).toFixed(0)} KB`;
    }
    return `${bytes} B`;
  };

  const handleSignIn = async () => {
    setReloginError(null);
    try {
      await forceRelogin(
        typeof navigator !== 'undefined' ? navigator : undefined,
        typeof window !== 'undefined' ? window.location : undefined,
        setReloginError
      );
    } catch {
      setReloginError(RELOGIN_FALLBACK_MESSAGE);
    }
  };

  // 1. Unauthenticated Screen (Cloudflare Access required)
  if (authStatus === 'unauthenticated') {
    return (
      <div class="pack-installer-card auth-gate-card">
        <div class="card-beacon auth-beacon" aria-hidden="true">
          <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </div>
        <div class="card-badge auth-badge">Private Beta Access</div>
        <h2 class="installer-card-title">Sign In Required</h2>
        <p class="installer-card-desc">
          Dérivée NYC is currently distributed as a private preview. Please sign in with your invited email via Cloudflare Access.
        </p>

        {reloginError && (
          <div class="installer-error-banner" role="alert">
            <div class="error-icon" aria-hidden="true">
              <svg viewBox="0 0 20 20" width="16" height="16" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <div class="error-content">
              <span class="error-msg">{reloginError}</span>
            </div>
          </div>
        )}

        <button
          type="button"
          class="installer-primary-btn"
          onClick={handleSignIn}
        >
          Sign In via Cloudflare Access
        </button>

        <div class="installer-subtext">
          Invitation list managed by Walsh. Access uses Email OTP (no password needed).
        </div>
      </div>
    );
  }

  // 2. Installed Pack Card (Compact dismissible banner + expandable detail card)
  if (packState && !isInstalling) {
    if (isDismissed) {
      return null;
    }

    const packLabel = packState.slug === 'nyc'
      ? 'NYC transit pack installed'
      : `${packState.displayName} transit pack installed`;

    return (
      <div class="pack-installed-panel">
        <div class="pack-installed-banner" role="status" aria-live="polite">
          <div class="pack-banner-info">
            <span class="pack-banner-check" aria-hidden="true">
              <svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.5">
                <polyline points="2.5 8.5 6 12 13.5 4.5" />
              </svg>
            </span>
            <span class="pack-banner-text">
              {packLabel} · {formatBytes(packState.totalBytes)}
            </span>
          </div>

          <div class="pack-banner-actions">
            <button
              type="button"
              class="pack-banner-btn pack-details-btn"
              onClick={handleToggleExpand}
              aria-expanded={effectiveExpanded}
              aria-label={effectiveExpanded ? 'Hide pack details' : 'Show pack details'}
              title={effectiveExpanded ? 'Hide pack details' : 'Show pack details'}
            >
              <span>{effectiveExpanded ? 'Hide' : 'Details'}</span>
              <svg
                class={`banner-chevron ${effectiveExpanded ? 'expanded' : ''}`}
                viewBox="0 0 16 16"
                width="11"
                height="11"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                aria-hidden="true"
              >
                <polyline points="4 6 8 10 12 6" />
              </svg>
            </button>
            <button
              type="button"
              class="pack-banner-btn pack-dismiss-btn"
              onClick={handleDismiss}
              aria-label="Dismiss transit pack banner"
              title="Dismiss"
            >
              <svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <line x1="3" y1="3" x2="13" y2="13" />
                <line x1="13" y1="3" x2="3" y2="13" />
              </svg>
            </button>
          </div>
        </div>

        {/* Update available affordance: calm one-row affordance */}
        {updateStatus === 'available' && availableUpdate && (
          <div class="pack-update-row" role="status">
            <div class="pack-update-info">
              <span class="pack-update-dot" aria-hidden="true" />
              <span class="pack-update-text">
                {packState.slug === 'nyc' ? 'NYC' : packState.displayName} pack v{availableUpdate.version} available · {formatBytes(availableUpdate.size, true)}
              </span>
            </div>
            <button
              type="button"
              class="pack-update-btn"
              onClick={handleStartUpdate}
              aria-label={`Update ${packState.displayName} pack to v${availableUpdate.version}`}
            >
              Update
            </button>
          </div>
        )}

        {/* Error state on update check failure */}
        {updateStatus === 'error' && isOnline && (
          <div class="pack-update-row pack-update-error-row" role="status">
            <span class="pack-update-error-text">
              {updateError || "Couldn't check for pack updates"}
            </span>
            <button
              type="button"
              class="pack-update-retry-btn"
              onClick={() => checkForUpdates(packState.slug)}
            >
              Retry
            </button>
          </div>
        )}

        {effectiveExpanded && (
          <div class="pack-installer-card installed-card pack-expanded-card">
            <div class="installer-header-row">
              <div class="installed-title-group">
                <div class="installed-status-tag">
                  <span class="status-live-dot" />
                  <span>Pack Installed</span>
                  {updateStatus === 'checking' && (
                    <span class="status-checking-subtle">· Checking for updates...</span>
                  )}
                  {updateStatus === 'up-to-date' && (
                    <span class="status-checking-subtle">· Up to date</span>
                  )}
                </div>
                <h2 class="installer-card-title">{packState.displayName} (v{packState.version})</h2>
                <div class="installer-season-label">{packState.seasonLabel}</div>
              </div>
              <button
                type="button"
                class="installer-reinstall-btn"
                onClick={handleReinstall}
                title="Re-download and verify pack"
              >
                Reinstall
              </button>
            </div>

            <div class="installer-meta-summary">
              <div class="summary-pill">
                <span class="pill-label">Total OPFS Size</span>
                <span class="pill-val">{formatBytes(packState.totalBytes)}</span>
              </div>
              <div class="summary-pill">
                <span class="pill-label">Files Verified</span>
                <span class="pill-val">{packState.files.length} / 6</span>
              </div>
              <div class="summary-pill">
                <span class="pill-label">Account</span>
                <span class="pill-val account-email">{userEmail || 'Local'}</span>
              </div>
            </div>

            <div class="installed-files-table-wrap">
              <div class="files-table-header">
                <span>Verified File</span>
                <span>Size</span>
              </div>
              <div class="files-list">
                {packState.files.map((file) => (
                  <div key={file.name} class="file-item-row">
                    <span class="file-item-name">
                      <svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.5">
                        <polyline points="3 8.5 6.5 12 13 4.5" />
                      </svg>
                      {file.name}
                    </span>
                    <span class="file-item-size">{formatBytes(file.size)}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  // 3. Installing / Downloading Progress Card
  if (isInstalling) {
    const percent = progress.percent ?? 0;
    const stageName =
      installStage === 'downloading'
        ? 'Downloading NYC Pack'
        : installStage === 'decompressing'
          ? 'Decompressing Archive'
          : installStage === 'writing'
            ? 'Writing to OPFS'
            : installStage === 'verifying'
              ? 'Verifying Integrity'
              : 'Installing';

    return (
      <div class="pack-installer-card installing-card">
        <div class="card-beacon installing-beacon" aria-hidden="true">
          <svg class="spinner-ring" viewBox="0 0 54 54" aria-hidden="true">
            <rect
              class="spinner-track"
              x="2"
              y="2"
              width="50"
              height="50"
              rx="13"
              fill="none"
              stroke="rgba(0, 229, 255, 0.2)"
              stroke-width="2"
            />
            <rect
              class="spinner-arc"
              x="2"
              y="2"
              width="50"
              height="50"
              rx="13"
              fill="none"
              stroke="var(--accent-cyan)"
              stroke-width="2.5"
              stroke-linecap="round"
              pathLength="100"
              stroke-dasharray="25 75"
            />
          </svg>
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
            <polyline points="7 10 12 15 17 10" />
            <line x1="12" y1="15" x2="12" y2="3" />
          </svg>
        </div>

        <div class="installer-stage-badge">
          <span class="stage-pulse-dot" />
          <span>{stageName}</span>
        </div>

        <h2 class="installer-card-title">Installing NYC Transit Pack</h2>

        <div class="progress-bar-container">
          <div class="progress-bar-track">
            <div class="progress-bar-fill" style={{ width: `${percent}%` }} />
          </div>
          <div class="progress-labels">
            <span>
              {installStage === 'downloading' && (
                <>
                  {formatBytes(progress.loadedBytes)} / {formatBytes(progress.totalBytes || 29688421)}
                </>
              )}
              {installStage === 'writing' && (
                <>
                  {progress.filesWritten ?? 0} of {progress.totalFiles ?? 6} files written ({progress.currentFile || 'writing'})
                </>
              )}
              {installStage === 'decompressing' && 'Decompressing Zstandard stream...'}
              {installStage === 'verifying' && 'Validating headers & SQLite signatures...'}
            </span>
            <span class="progress-percent-val">{percent}%</span>
          </div>
        </div>

        <div class="installer-notes-row">
          <span class="wake-lock-status">
            {wakeLockActive ? '🔒 Screen kept awake' : '⚠️ Keep browser foregrounded'}
          </span>
          <span class="installer-footnote">Do not close this tab until complete</span>
        </div>
      </div>
    );
  }

  // 4. Ready to Install Card
  return (
    <div class="pack-installer-card ready-card">
      <div class="card-beacon ready-beacon" aria-hidden="true">
        <svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="7 10 12 15 17 10" />
          <line x1="12" y1="15" x2="12" y2="3" />
        </svg>
      </div>

      <div class="card-badge ready-badge">
        <span>NYC Transit Pack Ready</span>
      </div>

      <h2 class="installer-card-title">Install NYC Transit Data</h2>
      <p class="installer-card-desc">
        Download the complete NYC subway routing graph, timetables, transfer shortcuts, and station geometries for 100% offline routing.
      </p>

      <div class="pack-specs-grid">
        <div class="spec-cell">
          <span class="spec-label">Download Size</span>
          <span class="spec-val">~29.7 MB (zstd)</span>
        </div>
        <div class="spec-cell">
          <span class="spec-label">Unpacked Size</span>
          <span class="spec-val">~65.3 MB (OPFS)</span>
        </div>
        <div class="spec-cell">
          <span class="spec-label">Storage Engine</span>
          <span class="spec-val">Origin Private FS</span>
        </div>
        <div class="spec-cell">
          <span class="spec-label">Authenticated As</span>
          <span class="spec-val user-email-val">{userEmail || 'Access Member'}</span>
        </div>
      </div>

      {errorMessage && (
        <div class="installer-error-banner" role="alert">
          <div class="error-icon" aria-hidden="true">
            <svg viewBox="0 0 20 20" width="16" height="16" fill="currentColor">
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <div class="error-content">
            <span class="error-title">Installation Stopped</span>
            <span class="error-msg">{errorMessage.text}</span>
          </div>
        </div>
      )}

      <div class="installer-actions-group">
        <button
          type="button"
          class="installer-primary-btn"
          onClick={() => startInstall()}
          disabled={!isOpfsSupported() || isVerifyingDisk}
        >
          {isVerifyingDisk ? 'Verifying Storage...' : 'Download NYC Pack (~30 MB)'}
        </button>

        {!isOpfsSupported() && (
          <div class="storage-warning">
            ⚠️ OPFS is not supported in this browser. Please use Safari 15.2+, Chrome, or Firefox.
          </div>
        )}
      </div>

      <div class="installer-subtext">
        Streams directly from Cloudflare Worker to browser sandbox. No cellular data used after install.
      </div>
    </div>
  );
}
