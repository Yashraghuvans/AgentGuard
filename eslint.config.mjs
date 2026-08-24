import js from '@eslint/js';

export default [
  {
    ignores: ['node_modules/', 'tools/', 'test-results/', '.sf/', 'force-app/main/default/lwc/**/jest.config.js']
  },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        process: 'readonly',
        console: 'readonly',
        Buffer: 'readonly',
        __dirname: 'readonly',
        require: 'readonly',
        module: 'readonly'
      }
    },
    rules: {
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      eqeqeq: 'error'
    }
  }
];
