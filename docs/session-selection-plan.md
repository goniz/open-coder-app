# Session Selection Feature Plan

## Overview
Add session selection dropdown in Chat tab, using OpenCodeAPIClient to query /sessions. Current session title serves as dropdown label and selector.

## Scope
- Update Sources/Views/ChatView.swift for UI dropdown
- Integrate in Sources/Views/WorkspaceInteractionView.swift for tab context
- Use Sources/DependencyClients/OpenCodeAPIClient.swift listSessions() to fetch sessions

## Steps
1. **API Integration**
   - Ensure listSessions() returns sessions with titles (add title field to OpenCodeSession if needed, default to formatted createdAt)

2. **State Management**
   - In ChatFeature: Add sessions array, currentSessionID, actions for fetching and selecting

3. **UI Implementation**
   - In ChatView: Add Menu at top:
     ```swift
     Menu {
       ForEach(store.sessions) { session in
         Button(session.title ?? session.id) { store.send(.selectSession(session.id)) }
       }
     } label: {
       Text(currentTitle)
     }
     ```
   - Handle selection: Update sessionID, reload messages via getMessages()

4. **WorkspaceInteractionView Integration**
   - Scope Chat tab with updated store
   - Fetch sessions on view load or tab select

5. **Testing & Edge Cases**
   - Test fetching, selection, message reload
   - Handle no sessions, errors, loading states
   - Add previews and unit tests

## Dependencies
- ComposableArchitecture for state/actions
- SwiftUI for Menu dropdown