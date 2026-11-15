"""Constructor guard for trainer subclasses that acquire extra resources."""

from functools import wraps


def close_on_error(initializer):
    @wraps(initializer)
    def guarded(self, *args, **kwargs):
        try:
            initializer(self, *args, **kwargs)
        except BaseException:
            if hasattr(self, "_resources"):
                self.close()
            raise

    return guarded
