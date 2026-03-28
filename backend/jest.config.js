module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/tests/unit/**/*.test.js'],
  coverageThreshold: {
    global: {
      lines: 70,
    },
  },
};
