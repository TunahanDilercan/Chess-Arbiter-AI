"use client";

import { useEffect, useState } from "react";
import { WifiOff } from "lucide-react";

// Shows a fixed banner whenever the browser loses its network connection.
// Uploads and analysis polling all go through the network, so a clear offline
// signal prevents the UI from looking silently broken.
export default function OfflineBanner() {
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    const update = () => setOffline(!navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  if (!offline) return null;

  return (
    <div className="offline-banner" role="status" aria-live="polite">
      <WifiOff size={16} strokeWidth={2} />
      You are offline — uploads and analysis are paused until the connection
      returns.
    </div>
  );
}
