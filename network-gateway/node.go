package main

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"path/filepath"
	"strconv"
	"strings"

	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tsnet"
)

type nodeStatus struct {
	State         string   `json:"state"`
	Hostname      string   `json:"hostname"`
	IPs           []string `json:"ips"`
	Enrolled      bool     `json:"enrolled"`
	ActiveStreams int      `json:"active_streams"`
}

type networkNode interface {
	Status(context.Context) (nodeStatus, error)
	Dial(context.Context, string, int) (net.Conn, error)
	Close() error
}

type tailscaleNode struct{ server *tsnet.Server }

func newTailscaleNode(dir string, key []byte, c connectionConfig, authKey string) (networkNode, error) {
	store, err := newSealedStore(filepath.Join(dir, "node.state"), c.identity(), key)
	if err != nil {
		return nil, err
	}
	s := &tsnet.Server{
		Dir: dir, Store: store, Hostname: c.Hostname, AuthKey: authKey,
		Logf: func(string, ...any) {}, UserLogf: func(string, ...any) {},
	}
	if err := s.Start(); err != nil {
		return nil, err
	}
	lc, err := s.LocalClient()
	if err != nil {
		s.Close()
		return nil, err
	}
	_, err = lc.EditPrefs(context.Background(), &ipn.MaskedPrefs{
		Prefs: ipn.Prefs{RouteAll: true, CorpDNS: false}, RouteAllSet: true, CorpDNSSet: true,
	})
	if err != nil {
		s.Close()
		return nil, err
	}
	return &tailscaleNode{s}, nil
}

func (n *tailscaleNode) Status(ctx context.Context) (nodeStatus, error) {
	lc, err := n.server.LocalClient()
	if err != nil {
		return nodeStatus{}, err
	}
	s, err := lc.Status(ctx)
	if err != nil {
		return nodeStatus{}, err
	}
	result := nodeStatus{State: s.BackendState, Enrolled: s.HaveNodeKey, IPs: []string{}}
	if s.Self != nil {
		result.Hostname = s.Self.DNSName
	}
	for _, ip := range s.TailscaleIPs {
		result.IPs = append(result.IPs, ip.String())
	}
	return result, nil
}

func (n *tailscaleNode) Dial(ctx context.Context, host string, port int) (net.Conn, error) {
	lc, err := n.server.LocalClient()
	if err != nil {
		return nil, err
	}
	s, err := lc.Status(ctx)
	if err != nil {
		return nil, err
	}
	if s.BackendState != "Running" {
		return nil, errors.New("tailnet is not ready")
	}
	// Resolve only against this node's netmap, never the host resolver. Dial the
	// resolved literal to prevent DNS rebinding or fallback to the SaaS network.
	ip, err := tailnetTarget(s, host)
	if err != nil {
		return nil, err
	}
	return n.server.Dial(ctx, "tcp", net.JoinHostPort(ip.String(), strconv.Itoa(port)))
}

func tailnetTarget(s *ipnstate.Status, host string) (netip.Addr, error) {
	host = strings.TrimSuffix(strings.ToLower(strings.Trim(host, "[]")), ".")
	ip, literal := netip.ParseAddr(host)
	for _, peer := range s.Peer {
		if peer.Expired {
			continue
		}
		name := strings.TrimSuffix(strings.ToLower(peer.DNSName), ".")
		if literal != nil && name != "" && (host == name || host == strings.Split(name, ".")[0]) {
			if len(peer.TailscaleIPs) > 0 {
				return peer.TailscaleIPs[0], nil
			}
		}
		if literal == nil {
			for _, peerIP := range peer.TailscaleIPs {
				if peerIP == ip {
					return ip, nil
				}
			}
			if peer.PrimaryRoutes != nil {
				for _, route := range peer.PrimaryRoutes.All() {
					// Default routes are exit nodes, not approved database subnets.
					if route.Bits() > 0 && route.Contains(ip) {
						return ip, nil
					}
				}
			}
		}
	}
	return netip.Addr{}, errors.New("destination is not a peer or approved subnet in this tailnet")
}

func (n *tailscaleNode) Close() error { return n.server.Close() }
