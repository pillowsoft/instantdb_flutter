import type { AppSchema } from './instant.schema';

type Rules = {
  attrs: {
    [EntityName in keyof AppSchema['entities']]: {
      [AttrName in keyof AppSchema['entities'][EntityName]]: {
        allow: {
          create?: any;
          read?: any;  
          update?: any;
          delete?: any;
        };
      };
    };
  };
};

const rules: Rules = {
  attrs: {
    // Allow all operations on todos for any user (demo app)
    todos: {
      id: { allow: { create: true, read: true, update: true, delete: true } },
      text: { allow: { create: true, read: true, update: true, delete: true } },
      completed: { allow: { create: true, read: true, update: true, delete: true } },
      createdAt: { allow: { create: true, read: true, update: true, delete: true } },
    },
    
    // Allow all operations on tiles for any user (demo app)
    tiles: {
      id: { allow: { create: true, read: true, update: true, delete: true } },
      row: { allow: { create: true, read: true, update: true, delete: true } },
      col: { allow: { create: true, read: true, update: true, delete: true } },
      userId: { allow: { create: true, read: true, update: true, delete: true } },
      userName: { allow: { create: true, read: true, update: true, delete: true } },
      color: { allow: { create: true, read: true, update: true, delete: true } },
      timestamp: { allow: { create: true, read: true, update: true, delete: true } },
    },
    
    // Allow all operations on messages for any user (demo app)
    messages: {
      id: { allow: { create: true, read: true, update: true, delete: true } },
      userId: { allow: { create: true, read: true, update: true, delete: true } },
      userName: { allow: { create: true, read: true, update: true, delete: true } },
      text: { allow: { create: true, read: true, update: true, delete: true } },
      timestamp: { allow: { create: true, read: true, update: true, delete: true } },
    },
  },
};

export default rules;