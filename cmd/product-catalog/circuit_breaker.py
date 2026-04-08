"""
Circuit Breaker implementation for downstream service protection.

Prevents cascading failures when a dependency (e.g., artist-service)
becomes unhealthy. States:
  - CLOSED: requests flow normally, failures are counted
  - OPEN: requests are rejected immediately (fail-fast)
  - HALF_OPEN: limited requests allowed to test recovery

This is critical for marketplace reliability — if the artist service
goes down, product pages should still load (with degraded data)
rather than timing out entirely.
"""

import asyncio
import logging
import time
from enum import Enum
from typing import Callable

logger = logging.getLogger("product-catalog")


class CircuitState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class CircuitBreakerOpenError(Exception):
    """Raised when the circuit breaker is open and rejecting requests."""
    pass


class CircuitBreaker:
    def __init__(
        self,
        name: str,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        half_open_max_calls: int = 3,
    ):
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls

        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._half_open_calls = 0
        self._last_failure_time = 0.0
        self._lock = asyncio.Lock()

    @property
    def state(self) -> CircuitState:
        if self._state == CircuitState.OPEN:
            # Check if recovery timeout has elapsed
            if time.time() - self._last_failure_time >= self.recovery_timeout:
                return CircuitState.HALF_OPEN
        return self._state

    async def call(self, func: Callable):
        """Execute a function with circuit breaker protection."""
        async with self._lock:
            current_state = self.state

            if current_state == CircuitState.OPEN:
                logger.warning(
                    f"Circuit breaker '{self.name}' is OPEN — rejecting request",
                    extra={"circuit_breaker": self.name, "state": "open"},
                )
                raise CircuitBreakerOpenError(
                    f"Circuit breaker '{self.name}' is open"
                )

            if current_state == CircuitState.HALF_OPEN:
                # Materialize the state transition from OPEN -> HALF_OPEN
                if self._state == CircuitState.OPEN:
                    self._transition_to(CircuitState.HALF_OPEN)
                if self._half_open_calls >= self.half_open_max_calls:
                    raise CircuitBreakerOpenError(
                        f"Circuit breaker '{self.name}' half-open call limit reached"
                    )
                self._half_open_calls += 1

        try:
            result = await func()
            await self._on_success()
            return result
        except Exception as e:
            await self._on_failure()
            raise

    async def _on_success(self):
        async with self._lock:
            if self.state == CircuitState.HALF_OPEN:
                self._success_count += 1
                if self._success_count >= self.half_open_max_calls:
                    self._transition_to(CircuitState.CLOSED)
            elif self._state == CircuitState.CLOSED:
                self._failure_count = 0

    async def _on_failure(self):
        async with self._lock:
            self._failure_count += 1
            self._last_failure_time = time.time()

            if self._state == CircuitState.HALF_OPEN:
                self._transition_to(CircuitState.OPEN)
            elif self._failure_count >= self.failure_threshold:
                self._transition_to(CircuitState.OPEN)

    def _transition_to(self, new_state: CircuitState):
        old_state = self._state
        self._state = new_state
        self._failure_count = 0
        self._success_count = 0
        self._half_open_calls = 0

        logger.info(
            f"Circuit breaker '{self.name}' transitioned: {old_state.value} -> {new_state.value}",
            extra={
                "circuit_breaker": self.name,
                "old_state": old_state.value,
                "new_state": new_state.value,
            },
        )
