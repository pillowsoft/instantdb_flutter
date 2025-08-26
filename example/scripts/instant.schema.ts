import { i } from '@instantdb/react';

const schema = i.schema({
  entities: {
    // Todo items - for the TodosPage
    todos: i.entity({
      id: i.string().unique(),
      text: i.string(),
      completed: i.boolean(),
      createdAt: i.number(),
    }),
    
    // Tile game tiles - for the TileGamePage collaborative painting
    tiles: i.entity({
      id: i.string().unique(),
      row: i.number(),
      col: i.number(), 
      userId: i.string(),
      userName: i.string(),
      color: i.number(),
      timestamp: i.number(),
    }),
    
    // Chat messages - for the TypingPage collaborative messaging  
    messages: i.entity({
      id: i.string().unique(),
      userId: i.string(),
      userName: i.string(),
      text: i.string(),
      timestamp: i.number(),
    }),
  },
  
  links: {},
});

// Export type for use in permissions
export type AppSchema = typeof schema;
export default schema;