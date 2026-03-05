import SwiftUI

struct AssistantTabView: View {
    @ObservedObject private var state = FridayState.shared
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background to prevent overlap
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Assistant Configuration")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(state.availableAgents) { agent in
                            agentRow(for: agent)
                        }
                    }
                    .padding(.bottom, 80) // Leave room for bottom pills
                }
            }
            .padding(.all, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func agentRow(for agent: BrainAgent) -> some View {
        let isSelected = state.activeAgentID == agent.id
        
        Button {
            Task {
                await LocalBrainProcessor.shared.switchAgent(id: agent.id)
                withAnimation { state.activeTab = .home }
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(agentColor(for: agent).opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: agentIcon(for: agent))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(agentColor(for: agent))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(agent.isLocal ? "Local Model" : "Cloud API")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 18))
                }
            }
            .padding(.all, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.cyan.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func agentColor(for agent: BrainAgent) -> Color {
        switch agent.type {
        case .gemini: return .blue
        case .qwen:   return .green
        case .llama:  return .orange
        case .custom: return .purple
        }
    }
    
    private func agentIcon(for agent: BrainAgent) -> String {
        switch agent.type {
        case .gemini: return "sparkles"
        case .qwen:   return "cpu"
        case .llama:  return "brain"
        case .custom: return "terminal"
        }
    }
}
