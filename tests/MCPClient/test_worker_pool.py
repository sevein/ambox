import os
import threading

from archivematica.MCPClient.client.pool import WorkerPool


def test_stop_skips_join_on_current_thread() -> None:
    pool = WorkerPool.__new__(WorkerPool)
    pool.shutdown_event = threading.Event()
    pool.pool_maintainance_thread = threading.current_thread()
    pool.workers = []
    pool.logging_listener = None

    pool.stop()


def test_stop_returns_in_non_parent_process() -> None:
    class Guard:
        def is_alive(self) -> bool:
            raise AssertionError("stop should not touch workers in child process")

    class ListenerGuard:
        def stop(self) -> None:
            raise AssertionError("stop should not stop listener in child process")

    pool = WorkerPool.__new__(WorkerPool)
    pool._parent_pid = os.getpid() + 1
    pool.shutdown_event = threading.Event()
    pool.pool_maintainance_thread = Guard()
    pool.workers = [Guard()]
    pool.logging_listener = ListenerGuard()

    pool.stop()
