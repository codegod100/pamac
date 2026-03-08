import sys
import os
import gi

# Ensure GObject Introspection can find Pamac
# In a real installation, these would be in standard paths
# For development, we rely on environment variables (GI_TYPELIB_PATH, LD_LIBRARY_PATH)

gi.require_version('Pamac', '11')
from gi.repository import Pamac, GLib

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Property, Signal

class PamacBackend(QObject):
    def __init__(self):
        super().__init__()
        # Use environment variable if provided, otherwise default to /etc/pamac.conf
        conf_path = os.environ.get("PAMAC_CONF", "/etc/pamac.conf")
        
        if not os.path.exists(conf_path):
            print(f"Warning: {conf_path} not found.")

        print(f"Using config: {conf_path}")
        self._config = Pamac.Config(conf_path=conf_path)
        self._db = Pamac.Database(config=self._config)
    
    @Slot(str, result="QVariantList")
    def search_packages(self, query):
        if not query:
            return []
        
        # search_pkgs returns a GenericArray of AlpmPackage
        pkgs = self._db.search_pkgs(query)
        results = []
        
        # In Python with PyGObject, GenericArray should be iterable
        for pkg in pkgs:
            results.append({
                "name": pkg.get_name(),
                "version": pkg.get_version(),
                "description": pkg.get_desc() if pkg.get_desc() else "",
                "repository": pkg.get_repo() if pkg.get_repo() else ""
            })
        return results

if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    
    engine = QQmlApplicationEngine()
    backend = PamacBackend()
    engine.rootContext().setContextProperty("pamacBackend", backend)
    
    # Load Kirigami
    qml_file = os.path.join(os.path.dirname(__file__), "Main.qml")
    engine.load(qml_file)
    
    if not engine.rootObjects():
        sys.exit(-1)
    
    sys.exit(app.exec())
