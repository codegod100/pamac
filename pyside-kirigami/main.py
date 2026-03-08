import sys
import os
import gi
import threading
import platform
import signal
import subprocess

# Ensure GObject Introspection can find Pamac
gi.require_version('Pamac', '11')
from gi.repository import Pamac, GLib

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Signal, QTimer

class PamacBackend(QObject):
    search_results_ready = Signal(list, int)
    search_started = Signal()
    status_message = Signal(str)

    def __init__(self):
        super().__init__()
        self._search_seq = 0
        self._search_cache = {}
        
        system_pacman_conf = "/etc/pacman.conf"
        user_config_dir = os.path.expanduser("~/.config/pamac")
        self.user_db_path = os.path.expanduser("~/.local/share/pamac")
        self.sync_dir = os.path.join(self.user_db_path, "sync")
        
        os.makedirs(user_config_dir, exist_ok=True)
        os.makedirs(self.sync_dir, exist_ok=True)
        
        # Setup environment
        os.environ["PACMAN_DBPATH"] = self.user_db_path
        os.environ["PACMAN_CONF"] = os.path.join(user_config_dir, "pacman.conf")
        self.conf_path = os.path.join(user_config_dir, "pamac.conf")
        os.environ["PAMAC_CONF"] = self.conf_path

        # Setup local pacman.conf if not on Arch
        if not os.path.exists(os.environ["PACMAN_CONF"]):
            with open(os.environ["PACMAN_CONF"], 'w') as f:
                f.write(f"[options]\nDBPath = {self.user_db_path}\nSigLevel = Never\n\n"
                        "[core]\nServer = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n"
                        "[extra]\nServer = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n")

        if not os.path.exists(self.conf_path):
            with open(self.conf_path, 'w') as f:
                f.write("EnableAUR\n")

        # Initializing Pamac objects
        self._config = Pamac.Config(conf_path=self.conf_path)
        self._config.set_enable_aur(True)
        self._db = Pamac.Database(config=self._config)
        self._transaction = Pamac.Transaction(database=self._db)
        
        threading.Thread(target=self._bg_maintenance, daemon=True).start()

    def _bg_maintenance(self):
        # Symlink system DBs if possible
        system_sync = "/var/lib/pacman/sync"
        if os.path.exists(system_sync):
            for db in ["core.db", "extra.db"]:
                src = os.path.join(system_sync, db)
                dst = os.path.join(self.sync_dir, db)
                if os.path.exists(src) and not os.path.exists(dst):
                    try: os.symlink(src, dst)
                    except: pass

        # Ensure AUR metadata
        aur_dest = os.path.join(self.sync_dir, "packages-meta-ext-v1.json.gz")
        if not os.path.exists(aur_dest):
            self.status_message.emit("Downloading AUR metadata...")
            self._download("https://aur.archlinux.org/packages-meta-ext-v1.json.gz", aur_dest)
        
        self.status_message.emit("Ready")
        GLib.idle_add(self._initial_refresh)

    def _download(self, url, dest):
        try:
            import urllib.request
            urllib.request.urlretrieve(url, dest)
        except: pass

    def _initial_refresh(self):
        self._transaction.check_dbs(None, lambda o, r: None)

    @Slot(str, str, result="QVariantMap")
    def get_package_details(self, name, repo):
        try:
            pkg = None
            if repo == "AUR":
                pkg = self._db.get_aur_pkg(name)
            else:
                pkg = self._db.get_sync_pkg(name)
            
            if not pkg: return {}

            details = {
                "name": pkg.props.name,
                "version": pkg.props.version,
                "description": pkg.props.desc or "",
                "repository": repo,
                "url": pkg.props.url or "",
                "license": pkg.props.license or "",
                "maintainer": "",
            }

            if repo == "AUR":
                details["votes"] = str(pkg.props.numvotes)
                details["popularity"] = f"{pkg.props.popularity:.2f}"
                details["maintainer"] = pkg.props.maintainer or "None"
            else:
                details["maintainer"] = pkg.props.packager or ""
            
            details["depends"] = []
            deps = pkg.props.depends
            if deps:
                try:
                    for i in range(1000):
                        try:
                            d = deps.get(i) if hasattr(deps, "get") else deps[i]
                            if d: details["depends"].append(str(d))
                            else: break
                        except: break
                except: pass
            return details
        except Exception as e:
            print(f"Failed to get details for {name}: {e}")
            return {}

    @Slot(str)
    def open_url(self, url):
        if not url: return
        opened = False
        for cmd in [["firefox", "--new-window"], ["google-chrome", "--new-window"], ["chromium", "--new-window"], ["brave", "--new-window"]]:
            try:
                subprocess.Popen(cmd + [url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                opened = True
                break
            except FileNotFoundError: continue
        if not opened:
            try:
                import webbrowser
                webbrowser.open_new(url)
            except: subprocess.Popen(["xdg-open", url])

    @Slot(str)
    def search_packages_async(self, query):
        self._search_seq += 1
        current_seq = self._search_seq
        print(f"DEBUG: Starting search for '{query}' (seq: {current_seq})")
        
        if query in self._search_cache:
            print(f"DEBUG: Cache hit for: {query}")
            GLib.idle_add(self.search_results_ready.emit, self._search_cache[query], current_seq)
            return

        self.search_started.emit()
        threading.Thread(target=self._perform_search, args=(query, current_seq), daemon=True).start()

    def _perform_search(self, query, seq):
        if not query or len(query) < 2:
            GLib.idle_add(self.search_results_ready.emit, [], seq)
            return
        results = []
        try:
            # Search official repos
            repo_pkgs = self._db.search_pkgs(query)
            print(f"DEBUG: Found {len(repo_pkgs)} repo results for '{query}'")
            for pkg in repo_pkgs:
                results.append({
                    "name": pkg.props.name,
                    "version": pkg.props.version,
                    "description": pkg.props.desc or "",
                    "repository": pkg.props.repo or "Repo"
                })
            
            results.sort(key=lambda x: x["name"])

            # Search AUR
            aur_pkgs = self._db.search_aur_pkgs(query)
            print(f"DEBUG: Found {len(aur_pkgs)} AUR results for '{query}'")
            for pkg in aur_pkgs:
                results.append({
                    "name": pkg.props.name,
                    "version": pkg.props.version,
                    "description": pkg.props.desc or "",
                    "repository": "AUR"
                })
            
            self._search_cache[query] = results
            
        except Exception as e:
            print(f"DEBUG: Search error: {e}")
        
        print(f"DEBUG: Emitting {len(results)} results for seq {seq}")
        GLib.idle_add(self.search_results_ready.emit, results, seq)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = QGuiApplication(sys.argv)
    timer = QTimer()
    timer.start(500)
    timer.timeout.connect(lambda: None)
    engine = QQmlApplicationEngine()
    backend = PamacBackend()
    engine.rootContext().setContextProperty("pamacBackend", backend)
    engine.load(os.path.join(os.path.dirname(__file__), "Main.qml"))
    if not engine.rootObjects():
        sys.exit(-1)
    sys.exit(app.exec())
