"""Tests for the circuit breaker implementation."""

import asyncio
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from circuit_breaker import CircuitBreaker, CircuitBreakerOpenError, CircuitState


@pytest.fixture
def breaker():
    return CircuitBreaker(
        name="test-service",
        failure_threshold=3,
        recovery_timeout=1.0,
        half_open_max_calls=2,
    )


@pytest.mark.asyncio
class TestCircuitBreaker:
    async def test_starts_closed(self, breaker):
        assert breaker.state == CircuitState.CLOSED

    async def test_successful_call(self, breaker):
        async def success():
            return "ok"
        result = await breaker.call(success)
        assert result == "ok"

    async def test_opens_after_threshold_failures(self, breaker):
        async def failing():
            raise Exception("fail")

        for _ in range(3):
            with pytest.raises(Exception, match="fail"):
                await breaker.call(failing)

        assert breaker.state == CircuitState.OPEN

    async def test_rejects_when_open(self, breaker):
        async def failing():
            raise Exception("fail")

        for _ in range(3):
            with pytest.raises(Exception):
                await breaker.call(failing)

        with pytest.raises(CircuitBreakerOpenError):
            await breaker.call(failing)

    async def test_transitions_to_half_open_after_timeout(self, breaker):
        async def failing():
            raise Exception("fail")

        for _ in range(3):
            with pytest.raises(Exception):
                await breaker.call(failing)

        assert breaker.state == CircuitState.OPEN

        # Wait for recovery timeout
        await asyncio.sleep(1.1)
        assert breaker.state == CircuitState.HALF_OPEN

    async def test_closes_after_successful_half_open_calls(self, breaker):
        async def failing():
            raise Exception("fail")

        async def success():
            return "ok"

        # Trip the breaker
        for _ in range(3):
            with pytest.raises(Exception):
                await breaker.call(failing)

        # Wait for recovery
        await asyncio.sleep(1.1)

        # Successful half-open calls should close it
        for _ in range(2):
            await breaker.call(success)

        assert breaker.state == CircuitState.CLOSED
