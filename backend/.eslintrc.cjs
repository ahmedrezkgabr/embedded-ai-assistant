module.exports = {
  extends: ['node'],
  env: {
    node: true,
    es6: true,
    jest: true,
  },
  parserOptions: {
    ecmaVersion: 2020,
  },
  rules: {
    'no-unused-vars': 'error',
    'no-undef': 'error',
    semi: ['error', 'always'],
    eqeqeq: ['error', 'always'],
    'import/no-commonjs': 'off',
    'no-empty-function': 'off',
  },
};
